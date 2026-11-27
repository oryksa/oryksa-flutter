import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Most lines kept on disk; the oldest go first.
const int _maxFiles = 300;

Directory _dir() => Directory('${Directory.systemTemp.path}${Platform.pathSeparator}oryksa_tv_voice');

File _file(String key) =>
    File('${_dir().path}${Platform.pathSeparator}${sha1.convert(utf8.encode(key)).toString()}.mp3');

/// The cached MP3 file of [key], or null.
Future<String?> oryksaTvCacheGet(String key) async {
  try {
    final f = _file(key);
    if (await f.exists() && await f.length() > 0) return f.path;
  } catch (_) {}
  return null;
}

/// Saves [mp3] under [key] and returns the file, or null when it cannot be written.
Future<String?> oryksaTvCachePut(String key, Uint8List mp3) async {
  try {
    final d = _dir();
    if (!await d.exists()) await d.create(recursive: true);
    final f = _file(key);
    await f.writeAsBytes(mp3, flush: true);
    await _prune(d);
    return f.path;
  } catch (_) {
    return null;
  }
}

Future<void> _prune(Directory d) async {
  try {
    final files = await d.list().where((e) => e is File && e.path.endsWith('.mp3')).cast<File>().toList();
    if (files.length <= _maxFiles) return;
    final stamped = <(File, DateTime)>[];
    for (final f in files) {
      stamped.add((f, await f.lastModified()));
    }
    stamped.sort((a, b) => a.$2.compareTo(b.$2));
    for (final s in stamped.take(files.length - _maxFiles)) {
      try {
        await s.$1.delete();
      } catch (_) {}
    }
  } catch (_) {}
}
