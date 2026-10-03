import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file's name and content, as picked by the user or downloaded from the
/// backend -- the one shape the backup/export features pass around.
class FileContent {
  const FileContent(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// Asks the user for a JSON file; null when they cancel.
typedef JsonFilePicker = Future<FileContent?> Function();

/// Hands [content] to the user as a file (a browser download on the web, a
/// save dialog elsewhere); false when they cancel.
typedef FileSaver = Future<bool> Function(FileContent content);

Future<FileContent?> _pickJsonFile() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
  if (file == null) return null;
  return FileContent(file.name, await file.readAsBytes());
}

Future<bool> _saveFile(FileContent content) async {
  final saved = await FilePicker.saveFile(
    fileName: content.name,
    bytes: content.bytes,
    mimeType: 'application/json',
  );
  // The web implementation always returns null -- it starts a browser
  // download and cannot tell whether that completed -- so null there is not
  // a cancellation.
  return kIsWeb || saved != null;
}

/// Providers rather than direct calls, so widget tests can substitute a fake
/// (the real pickers need a platform).
final jsonFilePickerProvider = Provider<JsonFilePicker>((ref) => _pickJsonFile);
final fileSaverProvider = Provider<FileSaver>((ref) => _saveFile);

/// The `filename="..."` of a `Content-Disposition` header, or [fallback].
String filenameFromContentDisposition(String? header, String fallback) {
  final match = RegExp(r'filename="?([^";]+)"?').firstMatch(header ?? '');
  return match?.group(1) ?? fallback;
}
