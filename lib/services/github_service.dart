import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:saturday_app/config/env_config.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Model for GitHub repository content
class GitHubContent {
  final String name;
  final String path;
  final String type; // 'file' or 'dir'
  final String? downloadUrl;
  final int size;

  GitHubContent({
    required this.name,
    required this.path,
    required this.type,
    this.downloadUrl,
    required this.size,
  });

  factory GitHubContent.fromJson(Map<String, dynamic> json) {
    return GitHubContent(
      name: json['name'] as String,
      path: json['path'] as String,
      type: json['type'] as String,
      downloadUrl: json['download_url'] as String?,
      size: json['size'] as int,
    );
  }

  bool get isDirectory => type == 'dir';
  bool get isFile => type == 'file';
}

/// Service for interacting with GitHub API
class GitHubService {
  static const String _apiBaseUrl = 'https://api.github.com';
  static const int _requestTimeout = 30; // seconds

  /// Get GitHub personal access token from environment
  String get _token => EnvConfig.githubToken;

  /// Get repository owner and name from environment
  String get _repoOwner => EnvConfig.githubRepoOwner;
  String get _repoName => EnvConfig.githubRepoName;

  /// Build authorization headers
  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Get contents of a directory in the repository
  ///
  /// [path] - Path to directory (empty string for root)
  /// Returns list of files and subdirectories
  Future<List<GitHubContent>> getDirectoryContents(String path) async {
    try {
      final cleanPath = path.isEmpty ? '' : path;
      final url = '$_apiBaseUrl/repos/$_repoOwner/$_repoName/contents/$cleanPath';

      AppLogger.info('Fetching GitHub directory contents: $cleanPath');

      final response = await http
          .get(
            Uri.parse(url),
            headers: _headers,
          )
          .timeout(const Duration(seconds: _requestTimeout));

      if (response.statusCode == 200) {
        final List<dynamic> json = jsonDecode(response.body);
        final contents = json.map((item) => GitHubContent.fromJson(item)).toList();

        AppLogger.info('Found ${contents.length} items in $cleanPath');
        return contents;
      } else if (response.statusCode == 404) {
        AppLogger.warning('Directory not found: $cleanPath');
        return [];
      } else {
        final errorBody = response.body;
        AppLogger.error('GitHub API error: ${response.statusCode} - $errorBody', null, null);
        throw Exception('GitHub API error: ${response.statusCode}');
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching GitHub directory contents', error, stackTrace);
      rethrow;
    }
  }

  /// Get contents of a file in the repository
  ///
  /// [path] - Path to file
  /// Returns file content as string
  Future<String> getFileContents(String path) async {
    try {
      AppLogger.info('Fetching GitHub file contents: $path');

      // First get the file metadata to get download URL
      final url = '$_apiBaseUrl/repos/$_repoOwner/$_repoName/contents/$path';
      final metadataResponse = await http
          .get(
            Uri.parse(url),
            headers: _headers,
          )
          .timeout(const Duration(seconds: _requestTimeout));

      if (metadataResponse.statusCode != 200) {
        throw Exception('Failed to fetch file metadata: ${metadataResponse.statusCode}');
      }

      final metadata = jsonDecode(metadataResponse.body);
      final downloadUrl = metadata['download_url'] as String?;

      if (downloadUrl == null) {
        throw Exception('No download URL available for file: $path');
      }

      // Download the actual file content
      final contentResponse = await http
          .get(Uri.parse(downloadUrl))
          .timeout(const Duration(seconds: _requestTimeout));

      if (contentResponse.statusCode == 200) {
        AppLogger.info('Successfully fetched file: $path (${contentResponse.body.length} bytes)');
        return contentResponse.body;
      } else {
        throw Exception('Failed to download file: ${contentResponse.statusCode}');
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching GitHub file contents', error, stackTrace);
      rethrow;
    }
  }

  /// Recursively get all gCode files from the repository
  ///
  /// [basePath] - Base path to start searching (default: '' for root)
  /// Returns list of all .gcode files found
  Future<List<GitHubContent>> getAllGCodeFiles({String basePath = ''}) async {
    final allFiles = <GitHubContent>[];

    try {
      final searchPath = basePath.isEmpty ? 'root' : basePath;
      AppLogger.info('Scanning for gCode files in: $searchPath');
      await _scanDirectory(basePath, allFiles);

      AppLogger.info('Found ${allFiles.length} gCode files in repository');
      return allFiles;
    } catch (error, stackTrace) {
      AppLogger.error('Error scanning for gCode files', error, stackTrace);
      rethrow;
    }
  }

  /// Recursively scan a directory for gCode files
  Future<void> _scanDirectory(String path, List<GitHubContent> accumulator) async {
    final contents = await getDirectoryContents(path);

    for (final item in contents) {
      if (item.isDirectory) {
        // Recursively scan subdirectories
        await _scanDirectory(item.path, accumulator);
      } else if (item.isFile && _isGCodeFile(item.name)) {
        // Add gCode files to accumulator
        accumulator.add(item);
      }
    }
  }

  /// Check if a filename represents a gCode file
  /// Supports common gCode file extensions: .gcode, .nc, .cnc, .g, .gco
  bool _isGCodeFile(String filename) {
    final lowerName = filename.toLowerCase();
    return lowerName.endsWith('.gcode') ||
           lowerName.endsWith('.nc') ||
           lowerName.endsWith('.cnc') ||
           lowerName.endsWith('.g') ||
           lowerName.endsWith('.gco');
  }

  /// Get README content from a directory
  ///
  /// [dirPath] - Path to directory containing README
  /// Returns README content or null if not found
  Future<String?> getReadme(String dirPath) async {
    try {
      // Try common README filenames
      const readmeNames = ['README.md', 'readme.md', 'README.MD', 'README'];

      for (final name in readmeNames) {
        try {
          final readmePath = dirPath.isEmpty ? name : '$dirPath/$name';
          final content = await getFileContents(readmePath);
          AppLogger.info('Found README at: $readmePath');
          return content;
        } catch (e) {
          // Try next filename
          continue;
        }
      }

      AppLogger.info('No README found in: $dirPath');
      return null;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching README', error, stackTrace);
      return null;
    }
  }

  /// Check if the GitHub token is valid
  /// Returns true if authenticated successfully
  Future<bool> validateToken() async {
    try {
      AppLogger.info('Validating GitHub token');

      final url = '$_apiBaseUrl/user';
      final response = await http
          .get(
            Uri.parse(url),
            headers: _headers,
          )
          .timeout(const Duration(seconds: _requestTimeout));

      if (response.statusCode == 200) {
        final user = jsonDecode(response.body);
        AppLogger.info('GitHub token valid for user: ${user['login']}');
        return true;
      } else {
        AppLogger.warning('GitHub token validation failed: ${response.statusCode}');
        return false;
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error validating GitHub token', error, stackTrace);
      return false;
    }
  }

  /// Get repository information
  Future<Map<String, dynamic>?> getRepositoryInfo() async {
    try {
      AppLogger.info('Fetching repository info');

      final url = '$_apiBaseUrl/repos/$_repoOwner/$_repoName';
      final response = await http
          .get(
            Uri.parse(url),
            headers: _headers,
          )
          .timeout(const Duration(seconds: _requestTimeout));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        AppLogger.warning('Failed to fetch repository info: ${response.statusCode}');
        return null;
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching repository info', error, stackTrace);
      return null;
    }
  }
}
