import 'dart:typed_data';

/// Web: no file system, nothing cached on disk.
Future<String?> oryksaTvCacheGet(String key) async => null;

/// Web: no file system. Returns null, so the voice plays from memory.
Future<String?> oryksaTvCachePut(String key, Uint8List mp3) async => null;
