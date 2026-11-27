import 'dart:async';

import 'package:flutter/foundation.dart';

import '../errors.dart';
import 'tv_core.dart';
import 'tv_models.dart';

/// Where the phone voice is.
enum OryksaPhoneVoiceState {
  /// Not started.
  idle,

  /// Asking the server for a code.
  creating,

  /// The QR is on screen, waiting for the phone.
  waiting,

  /// The phone is connected.
  paired,

  /// The person is speaking on the phone.
  listening,

  /// The phone closed the page (start again for a new code).
  phoneLeft,

  /// The code expired before the phone connected (start again for a new code).
  expired,

  /// The pairing ended.
  closed,

  /// The server could not be reached ([OryksaPhoneVoice.lastError]).
  error,
}

/// The phone as the microphone: the TV shows a QR, the phone opens the ORYKSA page and
/// what the person says arrives here as text ([texts], [onText]). For TVs that give no
/// microphone to apps (for example the Fire TV Stick). Get it from [OryksaTv.phoneVoice]
/// and show it with [OryksaPairingCard].
class OryksaPhoneVoice extends ChangeNotifier {
  /// Creates the phone voice of [tv]. Use [OryksaTv.phoneVoice].
  OryksaPhoneVoice(this.tv);

  /// The TV pieces.
  final OryksaTv tv;

  /// How long each events request waits on the server (long-poll).
  @visibleForTesting
  Duration pollWait = const Duration(seconds: 25);

  /// Pause before asking again after a network error.
  @visibleForTesting
  Duration retryPause = const Duration(seconds: 2);

  /// Called with each text the person said on the phone.
  void Function(String text)? onText;

  final StreamController<String> _texts = StreamController<String>.broadcast();
  OryksaPhoneVoiceState _state = OryksaPhoneVoiceState.idle;
  OryksaPairing? _pairing;
  Object? _lastError;
  String _lastText = '';
  int _gen = 0;
  bool _disposed = false;
  Timer? _expiry;

  /// Each text the person said on the phone.
  Stream<String> get texts => _texts.stream;

  /// Where it is.
  OryksaPhoneVoiceState get state => _state;

  /// The pairing on screen (QR and code), or null.
  OryksaPairing? get pairing => _pairing;

  /// The last error, when [state] is [OryksaPhoneVoiceState.error].
  Object? get lastError => _lastError;

  /// The last text heard.
  String get lastText => _lastText;

  /// True from [start] until [stop] (or the code expired or the pairing ended).
  bool get isActive => switch (_state) {
        OryksaPhoneVoiceState.creating ||
        OryksaPhoneVoiceState.waiting ||
        OryksaPhoneVoiceState.paired ||
        OryksaPhoneVoiceState.listening ||
        OryksaPhoneVoiceState.phoneLeft =>
          true,
        _ => false,
      };

  void _set(OryksaPhoneVoiceState s) {
    if (_disposed || _state == s) return;
    _state = s;
    notifyListeners();
  }

  /// Asks the server for a code and waits for the phone. Does nothing while already active.
  Future<void> start() async {
    if (_disposed || isActive) return;
    final my = ++_gen;
    _lastError = null;
    _set(OryksaPhoneVoiceState.creating);
    final OryksaPairing p;
    try {
      p = await tv.backend.pair(tv.locale);
    } catch (e) {
      if (my != _gen) return;
      _lastError = e;
      _set(OryksaPhoneVoiceState.error);
      return;
    }
    if (my != _gen || _disposed) {
      unawaited(_unpair(p.pairId));
      return;
    }
    _pairing = p;
    _set(OryksaPhoneVoiceState.waiting);
    notifyListeners();
    _expiry?.cancel();
    _expiry = Timer(p.expiresAt.difference(DateTime.now()), () {
      if (my == _gen && _state == OryksaPhoneVoiceState.waiting) _end(OryksaPhoneVoiceState.expired);
    });
    unawaited(_poll(my, p));
  }

  /// Ends the pairing (the phone page stops sending).
  Future<void> stop() async {
    _gen++;
    _expiry?.cancel();
    final p = _pairing;
    _pairing = null;
    _set(OryksaPhoneVoiceState.idle);
    if (p != null) await _unpair(p.pairId);
  }

  /// A new code: ends the current pairing and starts another.
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> _unpair(String id) async {
    try {
      await tv.backend.unpair(id);
    } catch (_) {}
  }

  void _end(OryksaPhoneVoiceState s) {
    _gen++;
    _expiry?.cancel();
    _set(s);
  }

  Future<void> _poll(int my, OryksaPairing p) async {
    var after = 0;
    while (my == _gen && !_disposed) {
      OryksaPhoneEventsPage page;
      try {
        page = await tv.backend.phoneEvents(p.pairId, after: after, wait: pollWait);
      } on OryksaException catch (e) {
        if (my != _gen) return;
        if (e.code == 'pair_expired' || e.status == 410) return _end(OryksaPhoneVoiceState.expired);
        if (e.code == 'pair_not_found' || e.status == 404) return _end(OryksaPhoneVoiceState.closed);
        await Future<void>.delayed(retryPause);
        continue;
      } catch (_) {
        if (my != _gen) return;
        await Future<void>.delayed(retryPause);
        continue;
      }
      if (my != _gen) return;
      after = page.next;
      for (final e in page.events) {
        if (my != _gen) return;
        _handle(e);
      }
      if (my != _gen) return;
      if (page.state == 'expired') return _end(OryksaPhoneVoiceState.expired);
      if (page.state == 'closed') return _end(OryksaPhoneVoiceState.closed);
    }
  }

  void _handle(OryksaPhoneEvent e) {
    switch (e.type) {
      case OryksaPhoneEventType.paired:
        _expiry?.cancel();
        _set(OryksaPhoneVoiceState.paired);
      case OryksaPhoneEventType.listening:
        _set(OryksaPhoneVoiceState.listening);
      case OryksaPhoneEventType.stopped:
        _set(OryksaPhoneVoiceState.paired);
      case OryksaPhoneEventType.text:
        _set(OryksaPhoneVoiceState.paired);
        final t = (e.text ?? '').trim();
        if (t.isNotEmpty && e.isFinal) {
          _lastText = t;
          notifyListeners();
          onText?.call(t);
          if (!_texts.isClosed) _texts.add(t);
        }
      case OryksaPhoneEventType.phoneLeft:
        _set(OryksaPhoneVoiceState.phoneLeft);
      case OryksaPhoneEventType.expired:
        _end(OryksaPhoneVoiceState.expired);
      case OryksaPhoneEventType.closed:
        _end(OryksaPhoneVoiceState.closed);
      case OryksaPhoneEventType.unknown:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _expiry?.cancel();
    final p = _pairing;
    _pairing = null;
    if (p != null) unawaited(_unpair(p.pairId));
    _texts.close();
    super.dispose();
  }
}
