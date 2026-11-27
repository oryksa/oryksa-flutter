import 'dart:async';
import 'dart:typed_data';

import '../errors.dart';
import '../models.dart';
import 'tv_backend.dart';
import 'tv_models.dart';

/// SIMULATED backend, for tests and demos only. It never calls ORYKSA, never counts
/// interactions and its texts are samples: nothing shown with it proves the real server.
///
/// Drive the phone from your test or demo with [phoneConnects], [phoneSays],
/// [phoneLeaves] and [expire].
class OryksaTvFakeBackend implements OryksaTvBackend {
  /// Creates the simulated backend.
  ///
  /// * [voice]: returns the MP3 for a text, or null for "no voice" (the default: the line is
  ///   counted and the presenter shows the subtitles only).
  /// * [chatReply]: the reply of the AI to a message.
  OryksaTvFakeBackend({
    this.platform = 'android_tv',
    this.voice,
    String Function(String message)? chatReply,
    this.delay = Duration.zero,
    this.fixedConfig,
  }) : _chatReply = chatReply ?? ((m) => '(simulated) You said: "$m"');

  @override
  final String platform;

  /// MP3 for a text, or null.
  final Uint8List? Function(String text, String locale)? voice;

  /// Fixed configuration (null: the sample one for the asked locale).
  final OryksaTvConfig? fixedConfig;

  final String Function(String message) _chatReply;

  /// Simulated time of each answer.
  final Duration delay;

  /// Calls to [speak] (each one is charged on the real server).
  int speakCalls = 0;

  /// What each [speak] asked: the text, whether a voice was wanted, and the voice revision of
  /// a line the device already had.
  final List<({String text, bool voice, String? cachedRev})> speakRequests = [];

  /// Messages sent with [chat].
  final List<String> sentMessages = [];

  /// Calls to [ai].
  int aiCalls = 0;

  /// Pairings ended with [unpair].
  final List<String> unpaired = [];

  int _pairs = 0;
  String? _pairId;
  int _seq = 0;
  String _state = 'waiting';
  final List<OryksaPhoneEvent> _events = [];
  Completer<void>? _wake;

  /// The locale the real server would choose for [requested] (the same rule as the
  /// approved voice table: the 8 locales, the rest English of the USA).
  static String resolveLocale(String requested) {
    final l = oryksaTvNormalizeLocale(requested);
    final lang = l.split('-').first;
    const latam = {'MX', 'AR', 'CO', 'CL', 'PE', 'VE', 'EC', 'GT', 'CU', 'BO', 'DO', 'HN', 'PY', 'SV', 'NI', 'CR', 'PA', 'UY', 'PR', '419', 'US'};
    final region = l.contains('-') ? l.split('-').last : '';
    switch (lang) {
      case 'pt':
        return region == 'BR' ? 'pt-BR' : 'pt-PT';
      case 'es':
        return latam.contains(region) ? 'es-419' : 'es-ES';
      case 'fr':
        return 'fr-FR';
      case 'de':
        return 'de-DE';
      case 'en':
        return region == 'GB' ? 'en-GB' : 'en-US';
      default:
        return 'en-US';
    }
  }

  /// Sample texts (English, and Portuguese of Brazil and of Portugal, never mixed): the real ones come from the
  /// server. Other languages use English, the only fallback language.
  static const Map<String, Map<String, String>> sampleTexts = {
    'en': {
      'assistant_title': '(simulated) Talk to ORYKSA',
      'assistant_hint': 'Pick a question or talk on your phone',
      'you': 'You',
      'thinking': 'Thinking…',
      'pair_title': 'Talk on your phone',
      'pair_step_scan': 'Point your phone camera at the code',
      'pair_step_code': 'Or open {url} and type {code}',
      'pair_waiting': 'Waiting for the phone…',
      'pair_connected': 'Phone connected',
      'pair_expired': 'The code expired',
      'listening': 'Listening…',
      'phone_left': 'The phone disconnected',
      'open_on_phone': 'Open on your phone',
      'retry': 'Try again',
      'close': 'Close',
      'error': 'Something went wrong. Try again.',
      'type_message': 'Type a message',
      'send': 'Send',
    },
    'pt-PT': {
      'assistant_title': '(simulado) Fala com a ORYKSA',
      'assistant_hint': 'Escolhe uma pergunta ou fala pelo telemóvel',
      'you': 'Tu',
      'thinking': 'A pensar…',
      'pair_title': 'Fala pelo telemóvel',
      'pair_step_scan': 'Aponta a câmara do telemóvel para o código',
      'pair_step_code': 'Ou abre {url} e escreve {code}',
      'pair_waiting': 'À espera do telemóvel…',
      'pair_connected': 'Telemóvel ligado',
      'pair_expired': 'O código expirou',
      'listening': 'A ouvir…',
      'phone_left': 'O telemóvel desligou-se',
      'open_on_phone': 'Abre no telemóvel',
      'retry': 'Tentar de novo',
      'close': 'Fechar',
      'error': 'Não deu. Tenta de novo.',
      'type_message': 'Escreve uma mensagem',
      'send': 'Enviar',
    },
    'pt-BR': {
      'assistant_title': '(simulado) Fale com a ORYKSA',
      'assistant_hint': 'Escolha uma pergunta ou fale pelo celular',
      'you': 'Você',
      'thinking': 'Pensando…',
      'pair_title': 'Fale pelo celular',
      'pair_step_scan': 'Aponte a câmera do celular para o código',
      'pair_step_code': 'Ou abra {url} e digite {code}',
      'pair_waiting': 'Esperando o celular…',
      'pair_connected': 'Celular conectado',
      'pair_expired': 'O código expirou',
      'listening': 'Ouvindo…',
      'phone_left': 'O celular desconectou',
      'open_on_phone': 'Abra no celular',
      'retry': 'Tentar de novo',
      'close': 'Fechar',
      'error': 'Não deu certo. Tente de novo.',
      'type_message': 'Digitar uma mensagem',
      'send': 'Enviar',
    },
  };

  /// The sample texts for a supported locale ([resolveLocale]): pt-BR, pt-PT, otherwise English.
  static Map<String, String> sampleTextsFor(String locale) => sampleTexts[locale] ?? sampleTexts['en']!;

  @override
  Future<OryksaTvConfig> config(String locale) async {
    if (fixedConfig != null) return fixedConfig!;
    await _wait();
    final l = resolveLocale(locale);
    final suggestions = switch (l) {
      'pt-BR' => const ['Como funciona?', 'O que você pode fazer?'],
      'pt-PT' => const ['Como funciona?', 'O que podes fazer?'],
      _ => const ['How does it work?', 'What can you do?'],
    };
    final phone = switch (l) {
      'pt-BR' => 'Falar pelo celular',
      'pt-PT' => 'Falar pelo telemóvel',
      _ => 'Talk on the phone',
    };
    return OryksaTvConfig(
      locale: l,
      voiceRev: 'sim-1',
      presenterName: 'ORYKSA',
      presenterAvatar: OryksaTvConfig.defaultAvatar,
      texts: OryksaTvTexts(sampleTextsFor(l)),
      suggestions: suggestions,
      actions: [OryksaTvAction(id: 'phone_voice', kind: OryksaTvActionKind.phoneVoice, label: phone)],
    );
  }
  @override
  Future<OryksaTvSpeech?> speak(String text, {required String locale, bool whisper = false, bool voice = true, String? cachedRev}) async {
    speakCalls++;
    speakRequests.add((text: text, voice: voice, cachedRev: cachedRev));
    await _wait();
    final l = resolveLocale(locale);
    // As the server should: every line is charged (1 here); with no voice wanted, a line the device already has (same
    // revision) or no voice for the locale, it only counts it and sends no voice.
    final none = OryksaTvSpeech(Uint8List(0), locale: l, voiceRev: 'sim-1', interactionsSpent: 1);
    if (!voice || cachedRev == 'sim-1') return none;
    final b = this.voice?.call(text, l);
    if (b == null || b.isEmpty) return none;
    return OryksaTvSpeech(b, locale: l, voiceRev: 'sim-1', interactionsSpent: 1);
  }

  @override
  Future<OryksaReply> chat(String message, {required String locale, OryksaAppContext? appContext, bool voice = false}) async {
    sentMessages.add(message);
    await _wait();
    final r = _chatReply(message);
    return OryksaReply(status: 'replied', reply: r, speech: voice ? r : null);
  }

  @override
  Future<OryksaAiResult> ai({String? instructions, String? input, Map<String, dynamic>? schema}) async {
    aiCalls++;
    await _wait();
    return OryksaAiResult(text: '(simulated) ${input ?? instructions ?? ''}'.trim(), interactionsSpent: 1);
  }

  /// Codes of the simulated pairings, in order (the real alphabet: no I, O, 0 or 1).
  static const List<String> codes = ['K7Q2MZ', 'H4PRWX', 'T9GBNE', 'D3VJSL'];

  /// The pair id of the [n]-th simulated pairing (1-based): `tvp_` and 12 hex, as the server.
  static String pairIdOf(int n) => 'tvp_${(0x5e1000000000 + n).toRadixString(16)}';

  bool _phone = false;

  @override
  Future<OryksaPairing> pair(String locale) async {
    await _wait();
    _pairs++;
    // As the server: a new pairing of the same TV closes the previous one.
    _pairId = pairIdOf(_pairs);
    _seq = 0;
    _state = 'waiting';
    _phone = false;
    _events.clear();
    final code = codes[(_pairs - 1) % codes.length];
    return OryksaPairing(
      pairId: _pairId!,
      code: code,
      url: 'https://oryksa.com/tv?c=$code',
      shortUrl: 'oryksa.com/tv',
      qrPngUrl: '',
      expiresIn: const Duration(minutes: 5),
    );
  }

  void _push(OryksaPhoneEventType type, {String? text, String? state}) {
    _events.add(OryksaPhoneEvent(seq: ++_seq, type: type, text: text, lang: text == null ? null : 'pt-PT'));
    if (state != null) _state = state;
    if (type == OryksaPhoneEventType.paired) _phone = true;
    if (type == OryksaPhoneEventType.phoneLeft || type == OryksaPhoneEventType.closed) _phone = false;
    final w = _wake;
    _wake = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  /// The phone opened the page.
  void phoneConnects() => _push(OryksaPhoneEventType.paired, state: 'paired');

  /// The person said [text] on the phone (a `listening` then a `text` event).
  void phoneSays(String text) {
    _push(OryksaPhoneEventType.listening);
    _push(OryksaPhoneEventType.text, text: text);
  }

  /// The phone closed the page.
  void phoneLeaves() => _push(OryksaPhoneEventType.phoneLeft);

  /// The code expired.
  void expire() => _push(OryksaPhoneEventType.expired, state: 'expired');

  @override
  Future<OryksaPhoneEventsPage> phoneEvents(String pairId, {int after = 0, Duration wait = const Duration(seconds: 25)}) async {
    if (pairId != _pairId) {
      return OryksaPhoneEventsPage(state: 'closed', next: after);
    }
    final ended = _state == 'expired' || _state == 'closed';
    // As the server: once ended, asking past the last event is 410 pair_expired.
    if (ended && after >= _seq) {
      throw const OryksaException(410, 'pair_expired', 'The pairing has ended.');
    }
    List<OryksaPhoneEvent> fresh() => _events.where((e) => e.seq > after).toList();
    if (fresh().isEmpty && !ended) {
      final w = _wake ??= Completer<void>();
      await w.future.timeout(wait.inSeconds > 30 ? const Duration(seconds: 30) : wait, onTimeout: () {});
    }
    final ev = fresh();
    return OryksaPhoneEventsPage(state: _state, next: ev.isEmpty ? after : ev.last.seq, events: ev, phoneConnected: _phone);
  }

  @override
  Future<void> unpair(String pairId) async {
    unpaired.add(pairId);
    if (pairId == _pairId) _push(OryksaPhoneEventType.closed, state: 'closed');
  }

  Future<void> _wait() => delay == Duration.zero ? Future<void>.value() : Future<void>.delayed(delay);
}
