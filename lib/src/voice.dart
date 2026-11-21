import 'dart:async';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../vad.dart';
import 'client.dart';
import 'models.dart';
import 'tts_file.dart';

/// What the voice conversation is doing now.
enum OryksaVoicePhase {
  /// Getting the microphone ready.
  starting,

  /// Listening: the customer can speak.
  listening,

  /// The customer is speaking (being recorded).
  hearing,

  /// Waiting for the answer.
  thinking,

  /// The AI is speaking. The customer can cut her off by speaking.
  speaking,

  /// Muted by the customer. Nothing is lost: everything stays in the chat.
  muted,

  /// The microphone is blocked or not delivering sound.
  micError,

  /// Too much background noise to tell a voice apart.
  noisy,

  /// The speech could not be understood; say it again.
  notUnderstood,
}

/// The ORYKSA voice conversation (the same behaviour as the ORYKSA app and every
/// other ORYKSA channel):
///
/// * the microphone stays open, even while she speaks;
/// * only a human voice cuts her off (keyboard, TV, birds and her own echo do not);
///   she stops on the word and the text stays in the chat;
/// * the beginning of the sentence that cut her is kept (the last second before);
/// * 700 ms of silence closes a sentence, 15 s is the longest sentence;
/// * a whisper gets a whispered, shorter answer;
/// * her voice is the ElevenLabs voice chosen in ORYKSA. If it fails she stays
///   silent and the text is shown: never a robot voice.
///
/// The decisions come from [Vad], the same engine as the ORYKSA app.
class OryksaVoiceController extends ChangeNotifier {
  /// Creates the controller. Call [start] to open the microphone.
  OryksaVoiceController({
    required this.client,
    this.appContext,
    this.onUserText,
    this.onReply,
    this.lang,
  });

  /// Client with the session token.
  final OryksaClient client;

  /// The language of your app screen (`en`, `pt`, `br`, `es`), sent with each message.
  final String? lang;

  /// Where the customer is in your app (sent with each message).
  final OryksaAppContext? Function()? appContext;

  /// Called with what the customer said (to show it in the chat).
  final void Function(String text)? onUserText;

  /// Called with the whole reply of the AI (to show it in the chat).
  final void Function(String text)? onReply;

  static const int _sr = 16000;

  /// One second of 16 kHz PCM16: kept while she speaks, so the start of the
  /// sentence that interrupts her is not lost.
  static const int _preRollBytes = _sr * 2;

  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  final vad = Vad(sampleRate: _sr);

  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<PlayerState>? _playSub;
  StreamSubscription<RecordState>? _recState;
  Timer? _micWatch;
  DateTime _lastChunk = DateTime.now();
  bool _restarting = false;
  String? _voiceFile;

  /// Microphone level (0 to 1), smoothed: the halo of the voice screen moves with it.
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  /// While the AI asks for a detail the customer should TYPE rather than say (`email`,
  /// `phone`, `name` or `details`), the voice screen shows a text box for it. Null otherwise.
  String? collecting;
  BytesBuilder _pcm = BytesBuilder();
  final List<Uint8List> _beforeCut = [];
  int _beforeCutBytes = 0;

  Timer? _deadMicGuard;
  bool _noEffects = false;
  bool _heardSomething = false;
  bool _closed = false;
  bool _speaking = false;
  bool _busy = false;
  bool _cutThisTurn = false;
  bool _whispered = false;
  int _noiseInARow = 0;
  int _turn = 0;

  OryksaVoicePhase _phase = OryksaVoicePhase.starting;

  /// Current phase (the voice screen shows it).
  OryksaVoicePhase get phase => _phase;

  /// Last thing the AI said (shown under the title while she speaks).
  String lastReply = '';

  /// What she said out loud last (the short spoken version of [lastReply]).
  String lastSpoken = '';

  /// Last thing the customer said.
  String lastHeard = '';

  void _set(OryksaVoicePhase p) {
    if (_closed || _phase == p) return;
    _phase = p;
    notifyListeners();
  }

  /// Opens the microphone and starts listening.
  Future<void> start() async {
    if (_closed || _pcmSub != null || _phase == OryksaVoicePhase.muted) return;
    await _audioSession();
    if (!await _rec.hasPermission()) {
      _set(OryksaVoicePhase.micError);
      return;
    }
    // Some Android phones (and the emulator) deliver digital silence with the
    // system echo cancellation on: start with it, and retry without it only then.
    var stream = await _openMic(effects: !_noEffects);
    if (stream == null && !_noEffects) {
      _noEffects = true;
      stream = await _openMic(effects: false);
    }
    if (stream == null) {
      _set(OryksaVoicePhase.micError);
      return;
    }
    vad.reset();
    _pcm = BytesBuilder();
    _heardSomething = false;
    _deadMicGuard?.cancel();
    _deadMicGuard = Timer(const Duration(seconds: 4), () {
      if (_closed || _heardSomething || _phase == OryksaVoicePhase.muted) return;
      _micIsDead();
    });
    if (!_busy && !_speaking) _set(OryksaVoicePhase.listening);
    _lastChunk = DateTime.now();
    _pcmSub = stream.listen(_onAudio, onError: (Object _) => _restartMic(), onDone: _restartMic);
    // The microphone must never die quietly (1.2.1 bug on Android: it paused when the AI's
    // voice started and never came back, so the screen stayed on "I'm listening").
    _recState ??= _rec.onStateChanged().listen((s) {
      if (s == RecordState.pause && !_closed && _phase != OryksaVoicePhase.muted) {
        _rec.resume().catchError((Object _) {});
      }
    }, onError: (Object _) {});
    _micWatch ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (_closed || _pcmSub == null || _phase == OryksaVoicePhase.muted || _restarting) return;
      if (DateTime.now().difference(_lastChunk) > const Duration(seconds: 3)) _restartMic();
    });
  }

  Future<void> _restartMic() async {
    if (_restarting || _closed || _phase == OryksaVoicePhase.muted) return;
    _restarting = true;
    try {
      await _stopMic();
      if (!_closed) await start();
    } finally {
      _restarting = false;
    }
  }

  /// Phone speaker + conversation mode, so she can hear the customer while she
  /// speaks without hearing herself.
  Future<void> _audioSession() async {
    try {
      final s = await AudioSession.instance;
      await s.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        // The recorder no longer takes audio focus (see _openMic): this is what quiets other apps.
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
      ));
      await s.setActive(true);
    } catch (_) {}
    await _androidSpeaker();
  }

  /// Android: the AI's voice plays as a conversation (voiceCommunication), and Android sends
  /// that to the earpiece, at call volume, unless the loudspeaker is chosen ("the voice is
  /// super low", TugaFreela app, 21/11/2026). Same as iOS (defaultToSpeaker) and the native
  /// Android SDK: conversation mode + loudspeaker. With a headset (wired, USB, Bluetooth or a
  /// hearing aid) nothing is forced: the voice goes to the headset as before.
  Future<void> _androidSpeaker() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final am = AndroidAudioManager();
      final outs = await am.getDevices(AndroidGetAudioDevicesFlags.outputs);
      if (outs.any((d) => _headsets.contains(d.type))) return;
      _oldMode ??= await am.getMode();
      await am.setMode(AndroidAudioHardwareMode.inCommunication);
      await am.setSpeakerphoneOn(true);
      _speakerOn = true;
      // Android ignores both calls when the app does not declare MODIFY_AUDIO_SETTINGS: then
      // her voice goes out as media (loudspeaker, media volume) instead of staying very low.
      if (!await am.isSpeakerphoneOn()) await _voiceAsMedia();
    } catch (_) {}
  }

  Future<void> _voiceAsMedia() async {
    final s = await AudioSession.instance;
    final c = s.configuration;
    if (c == null) return;
    await s.configure(c.copyWith(
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
    ));
  }

  /// Gives the phone back as it was (mode and loudspeaker) when the voice closes.
  Future<void> _androidSpeakerOff() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final am = AndroidAudioManager();
      if (_speakerOn) await am.setSpeakerphoneOn(false);
      if (_oldMode != null) await am.setMode(_oldMode!);
    } catch (_) {}
    _speakerOn = false;
    _oldMode = null;
  }

  static const _headsets = {
    AndroidAudioDeviceType.wiredHeadset,
    AndroidAudioDeviceType.wiredHeadphones,
    AndroidAudioDeviceType.bluetoothSco,
    AndroidAudioDeviceType.bluetoothA2dp,
    AndroidAudioDeviceType.usbHeadset,
    AndroidAudioDeviceType.hearingAid,
  };
  bool _speakerOn = false;
  AndroidAudioHardwareMode? _oldMode;

  Future<Stream<Uint8List>?> _openMic({required bool effects}) async {
    try {
      return await _rec.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sr,
        numChannels: 1,
        echoCancel: effects,
        noiseSuppress: effects,
        autoGain: effects,
        // Android (record_android >= 1.5): with the default `pause` the recorder takes audio
        // focus and pauses for good as soon as anything else asks for it, and the AI's own
        // voice (just_audio play -> AudioSession.setActive) does exactly that. Never pause.
        audioInterruption: AudioInterruptionMode.none,
      ));
    } catch (_) {
      return null;
    }
  }

  Future<void> _micIsDead() async {
    if (_closed) return;
    if (!_noEffects) {
      _noEffects = true;
      await _stopMic();
      if (!_closed) await start();
      return;
    }
    _set(OryksaVoicePhase.micError);
  }

  Future<void> _stopMic() async {
    _deadMicGuard?.cancel();
    _deadMicGuard = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    try {
      await _rec.stop();
    } catch (_) {}
  }

  void _onAudio(Uint8List chunk) {
    if (_closed || _phase == OryksaVoicePhase.muted || chunk.lengthInBytes < 2) return;
    _lastChunk = DateTime.now();
    final rms = Vad.rmsOf(chunk);
    level.value = level.value * .5 + rms * .5;
    if (!_heardSomething && rms > 0.0005) {
      _heardSomething = true;
      _deadMicGuard?.cancel();
    }

    // While she SPEAKS the engine only decides whether she was cut off.
    if (_speaking) {
      _beforeCut.add(chunk);
      _beforeCutBytes += chunk.lengthInBytes;
      while (_beforeCutBytes > _preRollBytes && _beforeCut.length > 1) {
        _beforeCutBytes -= _beforeCut.removeAt(0).lengthInBytes;
      }
      if (vad.feed(chunk, speaking: true).isBargeIn) _bargeIn();
      return;
    }
    // Waiting for her answer: a cough, the TV or an "hmm" must not open a second turn
    // (that bumped _turn and threw away the answer already on its way).
    if (_busy) return;

    final step = vad.feed(chunk);
    if (step.isBargeIn) {
      _bargeIn();
      return;
    }
    if (step.isCapturing || vad.capturing) {
      _pcm.add(chunk);
      if (!_busy) _set(OryksaVoicePhase.hearing);
    }
    if (!step.isDone) return;

    var raw = _pcm.takeBytes();
    _pcm = BytesBuilder();
    // Faster answers: send the sentence without its closing silence (keep 200 ms of it).
    final tail = (vad.quietMs - 200).clamp(0, 1 << 20) * (_sr * 2 ~/ 1000);
    if (tail > 0 && raw.length - tail > _sr) raw = Uint8List.sublistView(raw, 0, raw.length - tail);
    final whisper = vad.foiSussurro;
    final stats = _stats(empty: false, durMs: raw.length ~/ 32);
    vad.newTurn();
    if (step.enough && raw.length > _sr ~/ 2) {
      _noiseInARow = 0;
      _handle(_wav(raw), whisper, stats);
    } else if (step.isNoise) {
      if (++_noiseInARow >= 2) {
        _set(OryksaVoicePhase.noisy);
      }
    } else if (!_busy) {
      _set(OryksaVoicePhase.listening);
    }
  }

  /// The customer cut her off: stop the voice on the word, keep what he says.
  void _bargeIn() {
    _turn++;
    _speaking = false;
    _busy = false;
    try {
      _player.stop();
    } catch (_) {}
    _playSub?.cancel();
    vad.newTurn();
    vad.capturing = true;
    _pcm = BytesBuilder();
    for (final c in _beforeCut) {
      _pcm.add(c);
    }
    _beforeCut.clear();
    _beforeCutBytes = 0;
    _cutThisTurn = true;
    _set(OryksaVoicePhase.hearing);
  }

  /// Sends what was said right away (tap on the picture).
  void sendNow() {
    if (_busy || _speaking || !vad.capturing) return;
    final raw = _pcm.takeBytes();
    final whisper = vad.foiSussurro;
    final stats = _stats(empty: false, durMs: raw.length ~/ 32);
    vad.newTurn();
    _pcm = BytesBuilder();
    if (raw.length > _sr ~/ 2) _handle(_wav(raw), whisper, stats);
  }

  /// Audio numbers of this turn, in the ORYKSA ecosystem format (quality report).
  Map<String, dynamic> _stats({required bool empty, required int durMs}) => {
        'channel': 'sdk_flutter',
        'peak': double.parse(vad.picoDaFrase.toStringAsFixed(3)),
        'pitch': double.parse(vad.tomDaFrase.toStringAsFixed(3)),
        'noise': double.parse(vad.base.toStringAsFixed(3)),
        'floor': Vad.bargeFloor,
        'cut': false,
        'whisper': vad.foiSussurro,
        'self_cut': _cutThisTurn,
        'empty': empty,
        'dur_ms': durMs,
      };

  Future<void> _handle(Uint8List wav, bool whisper, Map<String, dynamic> stats) async {
    final my = ++_turn;
    _whispered = whisper;
    _busy = true;
    _set(OryksaVoicePhase.thinking);
    final text = await client.transcribe(wav);
    if (_closed || my != _turn) return;
    // Background noise transcribed as "." or "..." is not a message (no letter, no digit).
    if (text == null || text.isEmpty || !_hasWords(text)) {
      unawaited(client.voiceStats({...stats, 'empty': true}));
      _busy = false;
      _set(text == null ? OryksaVoicePhase.notUnderstood : OryksaVoicePhase.listening);
      return;
    }
    await _ask(text, my, whisper: whisper, stats: stats);
  }

  static final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static bool _hasWords(String s) => _wordChar.hasMatch(s);

  /// Sends what the customer TYPED in the voice screen (an e-mail or a phone number the AI
  /// asked for), and answers by voice like a spoken sentence.
  Future<void> sendText(String text) async {
    text = text.trim();
    if (text.isEmpty || _closed) return;
    if (_speaking) _bargeIn();
    vad.newTurn();
    _pcm = BytesBuilder();
    final my = ++_turn;
    _whispered = false;
    _busy = true;
    _set(OryksaVoicePhase.thinking);
    await _ask(text, my, whisper: false, stats: null);
  }

  Future<void> _ask(String text, int my, {required bool whisper, Map<String, dynamic>? stats}) async {
    lastHeard = text;
    onUserText?.call(text);
    OryksaReply? r;
    try {
      r = await client.sendAndWaitReply(text,
          appContext: appContext?.call(), voice: true, whisper: whisper, voiceStats: stats, lang: lang);
    } catch (_) {
      r = null;
    }
    if (_closed || my != _turn) return;
    final reply = (r?.reply ?? '').trim();
    final ask = (r?.collecting ?? '').trim().toLowerCase();
    collecting = ask.isEmpty ? null : ask;
    if (reply.isEmpty) {
      _busy = false;
      _set(OryksaVoicePhase.notUnderstood);
      return;
    }
    lastReply = reply;
    lastSpoken = (r?.speech ?? '').trim().isNotEmpty ? r!.speech!.trim() : reply;
    onReply?.call(reply);
    await _speak(lastSpoken, my);
  }

  /// Speaks [text] with the AI's voice. Used for the answers, and by your app for
  /// a greeting. If the voice fails she stays silent (the text is in the chat).
  Future<void> say(String text) {
    lastReply = text;
    lastSpoken = text;
    return _speak(text, ++_turn);
  }

  Future<void> _speak(String text, int my) async {
    _beforeCut.clear();
    _beforeCutBytes = 0;
    void done() {
      _cutThisTurn = false;
      _speaking = false;
      _busy = false;
      vad.newTurn();
      if (_closed || my != _turn) return;
      _set(OryksaVoicePhase.listening);
    }

    final mp3 = await client.tts(text, whisper: _whispered);
    if (_closed || my != _turn) {
      done();
      return;
    }
    if (mp3 == null || mp3.isEmpty) {
      done(); // never a robot voice: silence + the text in the chat
      return;
    }
    try {
      // Play from a temporary file: bytes from memory go through just_audio's http://127.0.0.1
      // proxy on Android, which Android 9+ blocks unless the app allows cleartext traffic
      // (1.2.1 bug: the voice never played). The web has no files: bytes from memory there.
      final old = _voiceFile;
      final path = await oryksaWriteVoiceFile(mp3, my);
      if (_closed || my != _turn) {
        await oryksaDeleteVoiceFile(path);
        done();
        return;
      }
      if (path != null) {
        _voiceFile = path;
        await _player.setFilePath(path);
      } else {
        await _player.setAudioSource(_Mp3Source(mp3));
      }
      if (old != null && old != path) unawaited(oryksaDeleteVoiceFile(old));
      _speaking = true;
      _set(OryksaVoicePhase.speaking);
      _playSub?.cancel();
      _playSub = _player.playerStateStream.listen((st) {
        if (st.processingState == ProcessingState.completed) {
          _playSub?.cancel();
          done();
        }
      });
      await _player.play();
    } catch (_) {
      done();
    }
  }

  /// Mute: she stops talking and stops listening. Nothing is lost: what she said
  /// stays in the chat. Call again to talk again.
  Future<void> toggleMute() async {
    if (_phase == OryksaVoicePhase.muted) {
      _phase = OryksaVoicePhase.starting;
      notifyListeners();
      await start();
      return;
    }
    _turn++;
    _speaking = false;
    _busy = false;
    _playSub?.cancel();
    await _stopMic();
    try {
      await _player.stop();
    } catch (_) {}
    vad.newTurn();
    _phase = OryksaVoicePhase.muted;
    notifyListeners();
  }

  /// Closes the microphone and the player.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _turn++;
    _micWatch?.cancel();
    await _recState?.cancel();
    _recState = null;
    await _stopMic();
    try {
      await _player.stop();
    } catch (_) {}
    await _playSub?.cancel();
    await oryksaDeleteVoiceFile(_voiceFile);
    _voiceFile = null;
    await _androidSpeakerOff();
    try {
      await (await AudioSession.instance).setActive(false); // give the audio back to other apps
    } catch (_) {}
  }

  @override
  void dispose() {
    _closed = true;
    _deadMicGuard?.cancel();
    _micWatch?.cancel();
    _recState?.cancel();
    _pcmSub?.cancel();
    _playSub?.cancel();
    unawaited(oryksaDeleteVoiceFile(_voiceFile));
    unawaited(_androidSpeakerOff());
    _rec.dispose();
    _player.dispose();
    level.dispose();
    super.dispose();
  }

  /// 16 kHz mono PCM16 WAV (what the server transcribes).
  static Uint8List _wav(Uint8List pcm) {
    const channels = 1, bits = 16;
    final h = ByteData(44);
    void tag(int off, String v) {
      for (var k = 0; k < v.length; k++) {
        h.setUint8(off + k, v.codeUnitAt(k));
      }
    }

    tag(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, channels, Endian.little);
    h.setUint32(24, _sr, Endian.little);
    h.setUint32(28, _sr * channels * bits ~/ 8, Endian.little);
    h.setUint16(32, channels * bits ~/ 8, Endian.little);
    h.setUint16(34, bits, Endian.little);
    tag(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder()
          ..add(h.buffer.asUint8List())
          ..add(pcm))
        .takeBytes();
  }

  /// Visible for tests.
  @visibleForTesting
  static Uint8List wavForTest(Uint8List pcm) => _wav(pcm);
}

/// Plays the MP3 bytes of the AI's voice without writing a file.
// StreamAudioSource is marked experimental in just_audio but is the supported way to play bytes.
// ignore: experimental_member_use
class _Mp3Source extends StreamAudioSource {
  _Mp3Source(this._bytes);
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
