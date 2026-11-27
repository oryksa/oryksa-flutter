import 'dart:async';

import 'package:flutter/foundation.dart';

import '../client.dart';
import '../errors.dart';
import 'tv_audio.dart';
import 'tv_backend.dart';
import 'tv_cache.dart';
import 'tv_models.dart';
import 'tv_phone_voice.dart';
import 'tv_text.dart';

/// The ORYKSA TV pieces of one app: the [presenter], the [phoneVoice] and the
/// configuration from the server. Create one and keep it while the app runs.
///
/// ```dart
/// final client = OryksaClient(getToken: myServerToken, platform: OryksaTvPlatform.fireTv.wire);
/// final tv = OryksaTv(client: client, locale: 'pt-BR');
/// await tv.presenter.say('Olá! Sou a ORYKSA.');
/// showOryksaTvAssistant(context, tv: tv);
/// ```
class OryksaTv extends ChangeNotifier {
  /// The TV pieces on the ORYKSA API through [client]. [locale] is the language of your app
  /// screen (BCP-47, for example `pt-BR`); by default the device's.
  OryksaTv({required OryksaClient client, String? locale, OryksaTvAudioPlayer Function()? audioPlayer})
      : this.withBackend(OryksaTvClientBackend(client), locale: locale, audioPlayer: audioPlayer);

  /// The TV pieces on any [backend], for example [OryksaTvFakeBackend] in tests and demos.
  OryksaTv.withBackend(this.backend, {String? locale, OryksaTvAudioPlayer Function()? audioPlayer})
      : _locale = oryksaTvNormalizeLocale(locale ?? oryksaTvLocaleTag(PlatformDispatcher.instance.locale)),
        _audioPlayer = audioPlayer;

  /// Where the pieces get their data.
  final OryksaTvBackend backend;
  final OryksaTvAudioPlayer Function()? _audioPlayer;

  String _locale;
  Future<OryksaTvConfig>? _config;
  String? _configFor;
  OryksaTvConfig? _current;
  bool _disposed = false;

  /// The language of the app screen (BCP-47), as given by the app.
  String get locale => _locale;

  /// Changes the language: the configuration is read again in the new one.
  set locale(String value) {
    final l = oryksaTvNormalizeLocale(value);
    if (l == _locale) return;
    _locale = l;
    _config = null;
    _current = null;
    if (!_disposed) notifyListeners();
  }

  /// The last configuration read from the server, or null before the first one.
  OryksaTvConfig? get currentConfig => _current;

  DateTime _configAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long the configuration is kept before it is read again (10 minutes). The business may change its voice,
  /// texts or rules while the app is open; a new voice_rev then also stops the old cached lines from playing.
  @visibleForTesting
  Duration configTtl = const Duration(minutes: 10);

  /// The TV configuration for [locale], kept for 10 minutes (pass [refresh] to read it again now).
  Future<OryksaTvConfig> config({bool refresh = false}) {
    final l = _locale;
    final fresh = DateTime.now().difference(_configAt) < configTtl;
    if (!refresh && fresh && _config != null && _configFor == l) return _config!;
    _configFor = l;
    _configAt = DateTime.now();
    return _config = _load(l);
  }

  /// The configuration is read again on the next use.
  void markConfigStale() => _configAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<OryksaTvConfig> _load(String l) async {
    try {
      final c = await backend.config(l);
      if (_configFor == l && !_disposed) {
        _current = c;
        notifyListeners();
      }
      return c;
    } catch (_) {
      if (_configFor == l) _config = null;
      rethrow;
    }
  }

  /// Like [config], but when the server cannot be reached returns a configuration with the
  /// English fallback texts (the pieces keep working, without the server's texts).
  Future<OryksaTvConfig> configOrFallback() async {
    try {
      return await config();
    } catch (e) {
      debugPrint('ORYKSA TV: could not read the configuration ($e); using the fallback.');
      return OryksaTvConfig(
        locale: _locale,
        presenterName: 'ORYKSA',
        presenterAvatar: OryksaTvConfig.defaultAvatar,
        fromServer: false,
      );
    }
  }

  /// The presenter: the AI speaks on screen with the voice of the locale and big subtitles.
  late final OryksaPresenter presenter = OryksaPresenter(this, player: _audioPlayer?.call());

  /// The phone as the microphone (QR).
  late final OryksaPhoneVoice phoneVoice = OryksaPhoneVoice(this);

  @override
  void dispose() {
    _disposed = true;
    presenter.dispose();
    phoneVoice.dispose();
    super.dispose();
  }
}

/// What the presenter is doing.
enum OryksaPresenterPhase {
  /// Quiet.
  idle,

  /// Getting the voice.
  preparing,

  /// Speaking (or showing the subtitles when there is no voice).
  speaking,
}

/// The presenter: the AI speaks on screen with the voice of the locale (from the server,
/// never in the code) and big subtitles. Get it from [OryksaTv.presenter] and show it with
/// [OryksaPresenterView].
///
/// Every line she says, or only shows, is charged each time by the ORYKSA interaction cost
/// table (per piece of up to 600 characters), a repeated line too: a spoken line at the voice
/// price, a subtitles-only line at the text price. The line appears only once the server has
/// counted it. Lines already said are kept on the device, so the server does not have to
/// make the same voice again.
class OryksaPresenter extends ChangeNotifier {
  /// Creates the presenter of [tv]. Use [OryksaTv.presenter].
  OryksaPresenter(this.tv, {OryksaTvAudioPlayer? player}) : _player = player ?? OryksaTvJustAudioPlayer();

  /// The TV pieces.
  final OryksaTv tv;
  final OryksaTvAudioPlayer _player;

  /// Called when she starts speaking (lower your music or video).
  VoidCallback? onStart;

  /// Called when she stops speaking.
  VoidCallback? onEnd;

  /// Called with errors (network, no interactions left, a line the server did not count).
  /// A line the server did not count is not shown.
  void Function(Object error)? onError;

  /// How long a subtitle stays on screen when there is no voice.
  @visibleForTesting
  Duration Function(String line) readingTime = oryksaTvReadingTime;

  OryksaPresenterPhase _phase = OryksaPresenterPhase.idle;
  String _line = '';
  String _text = '';
  int _turn = 0;
  bool _disposed = false;
  final List<Completer<void>> _sleeps = [];
  final Map<String, Uint8List> _mem = {};

  /// The voice revision the server sent for each locale (`X-ORYKSA-Voice-Rev`), used for
  /// the cache when the configuration has none (servers without the `tv` block): without
  /// it a kept line was not known as kept and its voice was made again (proven on the
  /// Fire TV, 26/11).
  final Map<String, String> _revByLocale = {};

  /// What she is doing.
  OryksaPresenterPhase get phase => _phase;

  /// True while she speaks or prepares to.
  bool get isBusy => _phase != OryksaPresenterPhase.idle;

  /// The subtitle on screen now.
  String get line => _line;

  /// The whole text she is saying.
  String get text => _text;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Says [text] (written by your app) in the locale of [tv], with subtitles. Completes when
  /// she finishes, is stopped or is given another text. Never throws: errors go to [onError].
  /// Each piece of the text is charged each time, even a line said before (at the voice
  /// price); a piece the server did not count is not shown, and she stops there.
  ///
  /// With [voice] `false` she shows the subtitles only, at reading speed, without any sound
  /// (for a TV without sound, at night, or a line that should only be read). Each piece is
  /// charged at the text price. OK and Back stop her as usual.
  Future<void> say(String text, {bool whisper = false, bool voice = true}) async {
    final my = ++_turn;
    await _halt();
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (my != _turn) return;
    if (t.isEmpty) {
      if (isBusy) _toIdle();
      return;
    }
    final wasIdle = !isBusy;
    _text = t;
    _line = '';
    _phase = OryksaPresenterPhase.preparing;
    _notify();
    if (wasIdle) onStart?.call();
    try {
      final cfg = await tv.configOrFallback();
      for (final chunk in oryksaTvSplitForSpeech(t, cfg.rules.presenterMaxChars)) {
        if (my != _turn) return;
        if (!await _speakChunk(chunk, cfg, whisper, voice, my)) return;
      }
    } catch (e) {
      onError?.call(e);
    } finally {
      if (my == _turn) _toIdle();
    }
  }

  /// Asks the AI to write a line ([instructions] and [input], as in `client.ai`) in the
  /// locale of [tv] and says it. Returns the text. Counts the ORYKSA interactions of the AI
  /// answer and of the line, as in [say] ([voice] `false`: the subtitles only, counted the
  /// same).
  Future<String> sayGenerated({required String instructions, String? input, bool whisper = false, bool voice = true}) async {
    final cfg = await tv.configOrFallback();
    final r = await tv.backend.ai(
      instructions: '$instructions\n\nWrite the answer in the language of the locale ${cfg.locale}, '
          'as plain text to be spoken aloud (no markdown, no lists, no emojis), '
          'at most ${cfg.rules.presenterMaxChars} characters.',
      input: input,
    );
    final text = r.text.trim();
    if (text.isNotEmpty) await say(text, whisper: whisper, voice: voice);
    return text;
  }

  /// Shows [lines] one by one at reading speed, with no sound.
  Future<void> _readOnly(List<String> lines, int my) async {
    for (final l in lines) {
      if (my != _turn) return;
      _show(l);
      await _sleep(readingTime(l));
    }
  }

  /// Stops speaking now.
  Future<void> stop() async {
    _turn++;
    await _halt();
    if (isBusy) _toIdle();
  }

  void _toIdle() {
    _phase = OryksaPresenterPhase.idle;
    _line = '';
    _text = '';
    _notify();
    if (!_disposed) onEnd?.call();
  }

  Future<void> _halt() async {
    for (final s in List.of(_sleeps)) {
      if (!s.isCompleted) s.complete();
    }
    _sleeps.clear();
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _sleep(Duration d) {
    final c = Completer<void>();
    _sleeps.add(c);
    final t = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future.whenComplete(() {
      t.cancel();
      _sleeps.remove(c);
    });
  }

  void _show(String line) {
    _line = line;
    _phase = OryksaPresenterPhase.speaking;
    _notify();
  }

  void _memPut(String key, Uint8List bytes) {
    if (_mem.length >= 30) _mem.remove(_mem.keys.first);
    _mem[key] = bytes;
  }

  /// Says one piece. False when the server did not count it: then nothing is shown and she stops.
  Future<bool> _speakChunk(String chunk, OryksaTvConfig cfg, bool whisper, bool voice, int my) async {
    String key(String? rev) => '${rev ?? '-'}|${cfg.locale}|${whisper ? 1 : 0}|$chunk';
    final rev0 = cfg.voiceRev ?? _revByLocale[cfg.locale];
    var k = key(rev0);
    String? file;
    Uint8List? bytes;
    if (voice) {
      file = await oryksaTvCacheGet(k);
      bytes = file == null ? _mem[k] : null;
    }
    final kept = file != null || bytes != null;
    // Every piece is asked of the server each time, even one the device already has: each time she says it, it
    // is charged (owner, 26/11/2026). For a kept line the server only charges it, with no new voice.
    OryksaTvSpeech? sp;
    try {
      sp = await tv.backend.speak(chunk, locale: cfg.locale, whisper: whisper, voice: voice, cachedRev: kept ? rev0 : null);
    } catch (e) {
      if (my == _turn) onError?.call(e);
      return false;
    }
    if (my != _turn) return false;
    if (sp == null || (sp.interactionsSpent ?? 0) < 1) {
      onError?.call(const OryksaException(0, 'not_counted', 'The server did not count this line, so it is not shown.'));
      return false;
    }
    if (voice && sp.bytes.isNotEmpty) {
      final rev = sp.voiceRev;
      if (rev != null && rev.isNotEmpty) _revByLocale[cfg.locale] = rev;
      // The server speaks with another voice than the configuration says: the business changed it, so the
      // configuration is read again and the old cached lines stop being used.
      if (rev != null && cfg.voiceRev != null && rev != cfg.voiceRev) tv.markConfigStale();
      k = key(sp.voiceRev ?? cfg.voiceRev);
      file = await oryksaTvCachePut(k, sp.bytes);
      bytes = null;
      if (file == null) {
        bytes = sp.bytes;
        _memPut(k, sp.bytes);
      }
    }
    if (my != _turn) return false;
    final lines = oryksaTvSubtitleLines(chunk);
    if (lines.isEmpty) return true;

    if (file == null && bytes == null) {
      // Counted, with no voice (asked for none, or none for this locale): the subtitles only, at reading speed.
      // Never a robot voice.
      await _readOnly(lines, my);
      return true;
    }

    Duration? len;
    try {
      len = await _player.load(file: file, bytes: bytes);
    } catch (e) {
      onError?.call(e);
      await _readOnly(lines, my);
      return true;
    }
    if (my != _turn) return false;

    // Each subtitle line gets its share of the audio by length (or the reading time when
    // the length of the audio is not known).
    final total = lines.fold<int>(0, (a, l) => a + l.length);
    final offsets = <Duration>[];
    var acc = 0;
    var readAcc = Duration.zero;
    for (final l in lines) {
      offsets.add(len != null && len > Duration.zero
          ? Duration(microseconds: (len.inMicroseconds * acc / total).round())
          : readAcc);
      acc += l.length;
      readAcc += readingTime(l);
    }
    _show(lines.first);
    final timers = <Timer>[
      for (var i = 1; i < lines.length; i++)
        Timer(offsets[i], () {
          if (my == _turn) _show(lines[i]);
        }),
    ];
    try {
      await _player.play();
    } catch (e) {
      onError?.call(e);
    } finally {
      for (final t in timers) {
        t.cancel();
      }
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _turn++;
    for (final s in List.of(_sleeps)) {
      if (!s.isCompleted) s.complete();
    }
    _sleeps.clear();
    unawaited(_player.dispose().catchError((_) {}));
    super.dispose();
  }
}
