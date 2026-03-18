import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf_render/pdf_render.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Service for PDF file operations
class PdfService {
  /// Extract text from PDF
  Future<String> extractText(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return '';
      }

      final bytes = await file.readAsBytes();
      final document = syncfusion.PdfDocument(inputBytes: bytes);

      final StringBuffer text = StringBuffer();
      for (int i = 0; i < document.pages.count; i++) {
        final pageText = syncfusion.PdfTextExtractor(
          document,
        ).extractText(startPageIndex: i, endPageIndex: i);
        text.writeln(pageText);
      }

      document.dispose();
      return text.toString();
    } catch (e) {
      print('Error extracting text from PDF: $e');
      return '';
    }
  }

  /// Extract title from PDF (uses metadata or first line of text)
  Future<String> extractTitle(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return p.basenameWithoutExtension(filePath);
      }

      final bytes = await file.readAsBytes();
      final document = syncfusion.PdfDocument(inputBytes: bytes);

      // Try PDF metadata title first
      try {
        final info = document.documentInformation;
        // ignore: unnecessary_null_comparison
        if (info != null && info.title != null && info.title.isNotEmpty) {
          document.dispose();
          return info.title;
        }
      } catch (_) {
        // Metadata access failed
      }

      // Try extracting from first page
      if (document.pages.count > 0) {
        final firstPageText = syncfusion.PdfTextExtractor(
          document,
        ).extractText(startPageIndex: 0, endPageIndex: 0);

        // Get first non-empty line as title
        final lines = firstPageText
            .split('\n')
            .where((l) => l.trim().isNotEmpty);
        if (lines.isNotEmpty) {
          var title = lines.first.trim();
          // Limit length
          if (title.length > 200) {
            title = title.substring(0, 200);
          }
          document.dispose();
          return title;
        }
      }

      document.dispose();
      return p.basenameWithoutExtension(filePath);
    } catch (e) {
      print('Error extracting title from PDF: $e');
      return p.basenameWithoutExtension(filePath);
    }
  }

  /// Check if file is a valid PDF
  static bool isPdf(String path) {
    return path.toLowerCase().endsWith('.pdf');
  }

  /// Open PDF with custom application
  static Future<bool> openWithCustomApp(String filePath, String appPath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      // Use open -a command on macOS for custom app
      final result = await Process.run('open', ['-a', appPath, filePath]);
      return result.exitCode == 0;
    } catch (e) {
      print('Error opening PDF with custom app: $e');
      return false;
    }
  }

  /// Open PDF with system default viewer
  static Future<bool> openWithSystemViewer(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      // Use open command on macOS
      final result = await Process.run('open', [filePath]);
      return result.exitCode == 0;
    } catch (e) {
      print('Error opening PDF: $e');
      return false;
    }
  }

  /// Reveal file in Finder
  static Future<bool> revealInFinder(String filePath) async {
    try {
      final result = await Process.run('open', ['-R', filePath]);
      return result.exitCode == 0;
    } catch (e) {
      print('Error revealing file: $e');
      return false;
    }
  }

  /// Generate thumbnail for a PDF to a specific output path.
  /// Used by entry scanner to store thumbnails in .papersuitecase/thumbnails/.
  static Future<String?> generateThumbnailToPath(
      String pdfPath, String outputPath) async {
    try {
      final thumbFile = File(outputPath);
      if (await thumbFile.exists()) return outputPath;
      await Directory(p.dirname(outputPath)).create(recursive: true);

      PdfDocument document;
      try {
        document = await PdfDocument.openFile(pdfPath);
      } catch (e) {
        final bytes = await File(pdfPath).readAsBytes();
        document = await PdfDocument.openData(bytes);
      }

      final page = await document.getPage(1);
      final width = 300;
      final height = (width * page.height / page.width).toInt();
      final pageImage = await page.render(width: width, height: height);

      final image = img.Image.fromBytes(
        width: pageImage.width,
        height: pageImage.height,
        bytes: pageImage.pixels.buffer,
        order: img.ChannelOrder.rgba,
        numChannels: 4,
      );

      final pngBytes = img.encodePng(image);
      await thumbFile.writeAsBytes(pngBytes);
      await document.dispose();
      return outputPath;
    } catch (e) {
      print('Error generating thumbnail to path: $e');
      return null;
    }
  }

}
