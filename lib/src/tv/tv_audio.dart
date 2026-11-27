import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// Plays the presenter's voice. The default is [OryksaTvJustAudioPlayer]; tests pass their own.
abstract class OryksaTvAudioPlayer {
  /// Loads an MP3 [file] (or [bytes] when there is no file, on the web) and returns its
  /// length when known.
  Future<Duration?> load({String? file, Uint8List? bytes});

  /// Plays what was loaded. Completes when it ends or is stopped.
  Future<void> play();

  /// Stops playing.
  Future<void> stop();

  /// Frees the player.
  Future<void> dispose();
}

/// The presenter's voice with just_audio. Plays from a file: bytes from memory go through
/// a local http://127.0.0.1 proxy on Android, which Android 9+ blocks unless the app allows
/// cleartext traffic (Fire TV with Fire OS 7 is Android 9).
class OryksaTvJustAudioPlayer implements OryksaTvAudioPlayer {
  final AudioPlayer _p = AudioPlayer();
  StreamSubscription<PlayerState>? _sub;
  Completer<void>? _done;

  void _finish() {
    _sub?.cancel();
    _sub = null;
    final d = _done;
    _done = null;
    if (d != null && !d.isCompleted) d.complete();
  }

  @override
  Future<Duration?> load({String? file, Uint8List? bytes}) async {
    if (file != null) return _p.setFilePath(file);
    if (bytes != null) return _p.setAudioSource(_BytesSource(bytes));
    return null;
  }

  @override
  Future<void> play() async {
    _finish();
    final done = _done = Completer<void>();
    _sub = _p.playerStateStream.listen((st) {
      if (st.processingState == ProcessingState.completed) _finish();
    }, onError: (_) => _finish());
    try {
      await _p.seek(Duration.zero);
      unawaited(_p.play().catchError((_) => _finish()));
    } catch (_) {
      _finish();
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    try {
      await _p.stop();
    } catch (_) {}
    _finish();
  }

  @override
  Future<void> dispose() async {
    _finish();
    await _p.dispose();
  }
}

// StreamAudioSource is marked experimental in just_audio but is the supported way to play bytes.
// ignore: experimental_member_use
class _BytesSource extends StreamAudioSource {
  _BytesSource(this._bytes);
  final Uint8List _bytes;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/mpeg',
    );
  }
}
