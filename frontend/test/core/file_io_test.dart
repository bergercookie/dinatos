import 'package:dinatos_frontend/core/file_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filenameFromContentDisposition', () {
    test('reads a quoted filename', () {
      expect(
        filenameFromContentDisposition(
          'attachment; filename="dinatos-backup-20261003-101500.json"',
          'fallback.json',
        ),
        'dinatos-backup-20261003-101500.json',
      );
    });

    test('reads an unquoted filename', () {
      expect(
        filenameFromContentDisposition('attachment; filename=export.json', 'fallback.json'),
        'export.json',
      );
    });

    test('falls back when the header is missing or has no filename', () {
      expect(filenameFromContentDisposition(null, 'fallback.json'), 'fallback.json');
      expect(filenameFromContentDisposition('attachment', 'fallback.json'), 'fallback.json');
    });
  });
}
