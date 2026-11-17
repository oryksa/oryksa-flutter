import 'dart:typed_data';

/// Web: no file system. Returns null, so the voice plays from memory.
Future<String?> oryksaWriteVoiceFile(Uint8List mp3, int turn) async => null;

/// Web: nothing to delete.
Future<void> oryksaDeleteVoiceFile(String? path) async {}
