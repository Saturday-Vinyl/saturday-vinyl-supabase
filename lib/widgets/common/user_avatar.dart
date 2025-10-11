import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';

enum AvatarSize {
  small,
  medium,
  large,
}

class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? displayName;
  final String? email;
  final AvatarSize size;

  const UserAvatar({
    super.key,
    this.photoUrl,
    this.displayName,
    this.email,
    this.size = AvatarSize.medium,
  });

  double get _diameter {
    switch (size) {
      case AvatarSize.small:
        return 32;
      case AvatarSize.medium:
        return 40;
      case AvatarSize.large:
        return 80;
    }
  }

  double get _fontSize {
    switch (size) {
      case AvatarSize.small:
        return 14;
      case AvatarSize.medium:
        return 16;
      case AvatarSize.large:
        return 32;
    }
  }

  String get _initials {
    if (displayName != null && displayName!.isNotEmpty) {
      return _getInitialsFromName(displayName!);
    }
    if (email != null && email!.isNotEmpty) {
      return _getInitialsFromEmail(email!);
    }
    return '?';
  }

  String _getInitialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    return '${parts[0].substring(0, 1)}${parts[parts.length - 1].substring(0, 1)}'
        .toUpperCase();
  }

  String _getInitialsFromEmail(String email) {
    final username = email.split('@').first;
    if (username.isEmpty) return '?';
    return username.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _diameter,
      height: _diameter,
      decoration: BoxDecoration(
        color: SaturdayColors.primaryDark,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                errorWidget: (context, url, error) => _buildInitialsAvatar(),
              )
            : _buildInitialsAvatar(),
      ),
    );
  }

  Widget _buildInitialsAvatar() {
    return Container(
      color: SaturdayColors.primaryDark,
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: _fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
