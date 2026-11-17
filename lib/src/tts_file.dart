// Where the AI's voice (MP3) is written before it plays: a temporary file on phones and
// desktop (dart:io), nothing on the web (the bytes play from memory there).
export 'tts_file_stub.dart' if (dart.library.io) 'tts_file_io.dart';
