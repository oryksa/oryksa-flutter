import 'dart:io';
import 'dart:typed_data';

/// Writes the AI's voice (MP3) to a temporary file and returns its path, or null when it
/// cannot be written. Playing a file needs nothing from the app. Playing bytes from memory
/// goes through a local http://127.0.0.1 proxy on Android, which Android 9+ blocks unless
/// the app allows cleartext traffic to localhost (the voice then never played: 1.2.1 bug).
Future<String?> oryksaWriteVoiceFile(Uint8List mp3, int turn) async {
  try {
    final dir = Directory.systemTemp;
    final f = File('${dir.path}${Platform.pathSeparator}oryksa_voice_${DateTime.now().microsecondsSinceEpoch}_$turn.mp3');
    await f.writeAsBytes(mp3, flush: true);
    return f.path;
  } catch (_) {
    return null;
  }
}

/// Deletes a voice file written by [oryksaWriteVoiceFile].
Future<void> oryksaDeleteVoiceFile(String? path) async {
  if (path == null) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
