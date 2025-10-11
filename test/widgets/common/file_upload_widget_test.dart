import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/widgets/common/file_upload_widget.dart';

void main() {
  group('FileUploadWidget', () {
    testWidgets('should display upload button when no file selected', (tester) async {
      bool pickFileCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileUploadWidget(
              onPickFile: () => pickFileCalled = true,
              label: 'Select File',
            ),
          ),
        ),
      );

      expect(find.text('Select File'), findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
      expect(find.byIcon(Icons.change_circle), findsNothing);

      await tester.tap(find.text('Select File'));
      expect(pickFileCalled, true);
    });

    testWidgets('should display file info when file is selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileUploadWidget(
              selectedFileName: 'test.pdf',
              selectedFileSize: 1024 * 1024, // 1 MB
              onPickFile: () {},
              label: 'Select File',
            ),
          ),
        ),
      );

      expect(find.text('test.pdf'), findsOneWidget);
      expect(find.text('1.0 MB'), findsOneWidget);
      expect(find.text('Change File'), findsOneWidget);
      expect(find.byIcon(Icons.change_circle), findsOneWidget);
    });

    testWidgets('should show clear button when onClearFile is provided', (tester) async {
      bool clearFileCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileUploadWidget(
              selectedFileName: 'test.pdf',
              selectedFileSize: 1024,
              onPickFile: () {},
              onClearFile: () => clearFileCalled = true,
              label: 'Select File',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(clearFileCalled, true);
    });

    testWidgets('should display help text when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileUploadWidget(
              onPickFile: () {},
              helpText: 'Select a PDF file',
              allowedExtensions: ['pdf', 'doc'],
              maxFileSizeMB: 10,
            ),
          ),
        ),
      );

      expect(find.textContaining('Select a PDF file'), findsOneWidget);
      expect(find.textContaining('pdf, doc'), findsOneWidget);
      expect(find.textContaining('10MB'), findsOneWidget);
    });

    testWidgets('should show correct icon for PDF files', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileUploadWidget(
              selectedFileName: 'document.pdf',
              onPickFile: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    });

    testWidgets('should show correct icon for image files', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileUploadWidget(
              selectedFileName: 'photo.jpg',
              onPickFile: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.image), findsOneWidget);
    });

    testWidgets('should show correct icon for video files', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileUploadWidget(
              selectedFileName: 'video.mp4',
              onPickFile: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.video_file), findsOneWidget);
    });
  });
}
