import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

/// The TV the app runs on, sent as `platform` to ORYKSA (so the owner's reports say
/// "in your app (Fire TV)"). A pure Dart package cannot tell a Fire TV from an Android TV:
/// your app says which one it is.
enum OryksaTvPlatform {
  /// Android TV and Google TV.
  androidTv('android_tv'),

  /// Amazon Fire TV with Fire OS.
  fireTv('fire_tv'),

  /// Amazon Fire TV with Vega OS.
  vega('vega'),

  /// Samsung (Tizen).
  tizen('tizen'),

  /// LG (webOS).
  webos('webos'),

  /// Hisense (VIDAA).
  vidaa('vidaa'),

  /// Apple TV.
  tvos('tvos'),

  /// Roku.
  roku('roku');

  const OryksaTvPlatform(this.wire);

  /// The value sent to the API.
  final String wire;
}

/// BCP-47 tag of a [Locale] with a hyphen: `pt-BR`, `es-419`, `en`.
String oryksaTvLocaleTag(Locale l) {
  final parts = <String>[l.languageCode];
  if ((l.scriptCode ?? '').isNotEmpty) parts.add(l.scriptCode!);
  if ((l.countryCode ?? '').isNotEmpty) parts.add(l.countryCode!);
  return parts.join('-');
}

/// Normalises a locale string (`pt_BR`, `pt-br`, `PT-BR`) to `pt-BR`. Empty stays empty.
String oryksaTvNormalizeLocale(String raw) {
  final p = raw.trim().replaceAll('_', '-').split('-').where((s) => s.isNotEmpty).toList();
  if (p.isEmpty) return '';
  final out = <String>[p.first.toLowerCase()];
  for (final s in p.skip(1)) {
    if (s.length == 4) {
      out.add(s[0].toUpperCase() + s.substring(1).toLowerCase()); // script, e.g. Latn
    } else {
      out.add(s.toUpperCase()); // region, e.g. BR or 419
    }
  }
  return out.join('-');
}

/// The language code the chat endpoint has always taken (`en`, `pt`, `br`, `es`...):
/// `pt-BR` is `br`, any other Portuguese is `pt`, the rest is the language code.
String oryksaTvChatLang(String locale) {
  final l = oryksaTvNormalizeLocale(locale);
  if (l.isEmpty) return '';
  final lang = l.split('-').first;
  if (lang == 'pt') return l == 'pt-BR' ? 'br' : 'pt';
  return lang;
}

/// What a button of the assistant panel does ([OryksaTvAction.kind]).
enum OryksaTvActionKind {
  /// Sends [OryksaTvAction.message] to the AI.
  message,

  /// Opens the QR to talk on the phone.
  phoneVoice,

  /// Closes the panel.
  close,
}

/// A button of the assistant panel, from the ORYKSA server (`tv.actions`).
@immutable
class OryksaTvAction {
  /// Creates a button.
  const OryksaTvAction({required this.id, required this.kind, required this.label, this.message});

  /// Reads one entry of `tv.actions`. Null when the kind is unknown or the label is empty.
  static OryksaTvAction? fromJson(Map<String, dynamic> j) {
    final label = (j['label'] ?? '').toString().trim();
    if (label.isEmpty) return null;
    final kind = switch ((j['kind'] ?? '').toString()) {
      'message' => OryksaTvActionKind.message,
      'phone_voice' => OryksaTvActionKind.phoneVoice,
      'close' => OryksaTvActionKind.close,
      _ => null,
    };
    if (kind == null) return null;
    final message = j['message']?.toString().trim();
    if (kind == OryksaTvActionKind.message && (message == null || message.isEmpty)) return null;
    return OryksaTvAction(id: (j['id'] ?? label).toString(), kind: kind, label: label, message: message);
  }

  /// Id of the button.
  final String id;

  /// What it does.
  final OryksaTvActionKind kind;

  /// Text on the button.
  final String label;

  /// For [OryksaTvActionKind.message]: what is sent to the AI.
  final String? message;
}

/// Rules of the TV pieces, from the ORYKSA server (`tv.rules`).
@immutable
class OryksaTvRules {
  /// Creates the rules.
  const OryksaTvRules({
    this.phoneVoice = true,
    this.tvMic = 'auto',
    this.speakReplies = true,
    this.presenterMaxChars = 600,
  });

  /// Reads `tv.rules`.
  factory OryksaTvRules.fromJson(Map<String, dynamic> j) {
    final max = (j['presenter_max_chars'] as num?)?.toInt();
    return OryksaTvRules(
      phoneVoice: j['phone_voice'] != false,
      tvMic: j['tv_mic']?.toString() == 'off' ? 'off' : 'auto',
      speakReplies: j['speak_replies'] != false,
      presenterMaxChars: (max != null && max >= 40) ? max : 600,
    );
  }

  /// The phone can be the microphone (QR).
  final bool phoneVoice;

  /// `auto`: use the TV microphone when the device has one. `off`: never.
  final String tvMic;

  /// The assistant panel reads its replies with the presenter's voice.
  final bool speakReplies;

  /// Longest text the server speaks in one go: longer texts are split.
  final int presenterMaxChars;
}

/// The texts of the TV pieces, from the ORYKSA server (`tv.texts`), already in the locale
/// the server chose. A missing key uses a short English text and is logged once.
@immutable
class OryksaTvTexts {
  /// Creates the texts.
  const OryksaTvTexts(this.values);

  /// Short English texts used only when the server does not send a key (older servers).
  static const Map<String, String> fallback = {
    'assistant_title': 'Ask the AI',
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
  };

  static final Set<String> _warned = {};

  /// Texts by key.
  final Map<String, String> values;

  /// The text for [key], with `{name}` placeholders replaced by [vars].
  String get(String key, [Map<String, String> vars = const {}]) {
    var s = values[key];
    if (s == null || s.trim().isEmpty) {
      if (_warned.add(key)) debugPrint('ORYKSA TV: the server sent no text for "$key"; using the English fallback.');
      s = fallback[key] ?? key;
    }
    vars.forEach((k, v) => s = s!.replaceAll('{$k}', v));
    return s!;
  }
}

/// Everything the TV pieces read from the server: `GET /v1/client/agent?locale=...`, block `tv`.
@immutable
class OryksaTvConfig {
  /// Creates a configuration.
  const OryksaTvConfig({
    required this.locale,
    required this.presenterName,
    required this.presenterAvatar,
    this.voiceRev,
    this.texts = const OryksaTvTexts({}),
    this.suggestions = const [],
    this.actions = const [],
    this.rules = const OryksaTvRules(),
    this.fromServer = true,
  });

  /// Default photo of the AI when the server sends none.
  static const String defaultAvatar = 'https://oryksa.com/assets/img/avatar_official_oryksa.png';

  /// Reads the answer of `GET /v1/client/agent?locale=...`. Without a `tv` block (older
  /// servers) [fromServer] is false and the texts are the English fallback.
  factory OryksaTvConfig.fromAgentJson(Map<String, dynamic> j, {required String requestedLocale}) {
    Map<String, dynamic> map(dynamic v) => v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
    String? text(dynamic v) {
      if (v is! String) return null;
      final s = v.trim();
      return s.isEmpty ? null : s;
    }

    final tv = j['tv'] is Map ? map(j['tv']) : null;
    final t = tv ?? const <String, dynamic>{};
    final presenter = map(t['presenter']);
    final texts = map(t['texts']).map((k, v) => MapEntry(k, '$v'));
    final sugg = t['suggestions'] is List
        ? (t['suggestions'] as List).map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final actions = t['actions'] is List
        ? (t['actions'] as List).whereType<Map>().map((m) => OryksaTvAction.fromJson(m.cast<String, dynamic>())).whereType<OryksaTvAction>().toList()
        : <OryksaTvAction>[];
    if (tv == null) debugPrint('ORYKSA TV: the server sent no "tv" block in /client/agent; using the English fallback.');
    return OryksaTvConfig(
      locale: text(t['locale']) ?? oryksaTvNormalizeLocale(requestedLocale),
      voiceRev: text(t['voice_rev']),
      presenterName: text(presenter['name']) ?? text(j['name']) ?? 'ORYKSA',
      presenterAvatar: text(presenter['avatar']) ?? text(j['avatar']) ?? defaultAvatar,
      texts: OryksaTvTexts(texts),
      suggestions: sugg,
      actions: actions,
      rules: OryksaTvRules.fromJson(map(t['rules'])),
      fromServer: tv != null,
    );
  }

  /// The locale the server chose (one of the supported ones), for example `pt-BR`.
  final String locale;

  /// Changes when the business changes the voice of this locale (keys the voice cache).
  final String? voiceRev;

  /// Name of the presenter (the AI), for example `ORYKSA`.
  final String presenterName;

  /// Photo of the presenter.
  final String presenterAvatar;

  /// Texts of the TV pieces.
  final OryksaTvTexts texts;

  /// Suggested questions for the assistant panel.
  final List<String> suggestions;

  /// Buttons of the assistant panel.
  final List<OryksaTvAction> actions;

  /// Rules.
  final OryksaTvRules rules;

  /// False when the server sent no `tv` block (older servers).
  final bool fromServer;
}

/// The presenter's voice for one text ([OryksaTvBackend.speak]).
@immutable
class OryksaTvSpeech {
  /// Creates a speech.
  const OryksaTvSpeech(this.bytes, {required this.locale, this.voiceRev, this.interactionsSpent});

  /// MP3 bytes. Empty when the server only counted the line: subtitles only, or a line the
  /// device already has.
  final Uint8List bytes;

  /// Locale the server spoke in (`X-ORYKSA-Locale`).
  final String locale;

  /// Voice revision (`X-ORYKSA-Voice-Rev`).
  final String? voiceRev;

  /// Interactions this speech used (`X-ORYKSA-Interactions-Spent`).
  final int? interactionsSpent;
}

/// A phone pairing ([OryksaTvBackend.pair]): the QR and the code shown on the TV.
@immutable
class OryksaPairing {
  /// Creates a pairing.
  OryksaPairing({
    required this.pairId,
    required this.code,
    required this.url,
    required this.shortUrl,
    required this.qrPngUrl,
    required this.expiresIn,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Reads the answer of `POST /v1/client/tv/pair`.
  factory OryksaPairing.fromJson(Map<String, dynamic> j) {
    final id = (j['pair_id'] ?? '').toString();
    final code = (j['code'] ?? '').toString();
    if (id.isEmpty || code.isEmpty) throw const FormatException('The pairing has no pair_id or code.');
    final url = (j['url'] ?? '').toString();
    return OryksaPairing(
      pairId: id,
      code: code,
      url: url,
      shortUrl: (j['short_url'] ?? url).toString(),
      qrPngUrl: (j['qr_png_url'] ?? '').toString(),
      expiresIn: Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 300),
    );
  }

  /// Id of the pairing.
  final String pairId;

  /// Short code the person can type on the phone.
  final String code;

  /// What the QR opens.
  final String url;

  /// Short address shown under the QR.
  final String shortUrl;

  /// PNG of the QR (empty: the TV shows the code only).
  final String qrPngUrl;

  /// Time to pair before the code expires.
  final Duration expiresIn;

  /// When the pairing was created on this device.
  final DateTime createdAt;

  /// When the code expires.
  DateTime get expiresAt => createdAt.add(expiresIn);
}

/// Kind of [OryksaPhoneEvent].
enum OryksaPhoneEventType {
  /// The phone opened the page with the code.
  paired,

  /// The person is speaking.
  listening,

  /// The person stopped and nothing was heard.
  stopped,

  /// What the person said ([OryksaPhoneEvent.text]).
  text,

  /// The phone closed the page or lost the connection.
  phoneLeft,

  /// The code expired before pairing.
  expired,

  /// The TV or the server ended the pairing.
  closed,

  /// A type this SDK does not know (newer servers): ignored.
  unknown,
}

/// One event of the phone, from `GET /v1/client/tv/pair/{id}/events`.
@immutable
class OryksaPhoneEvent {
  /// Creates an event.
  const OryksaPhoneEvent({required this.seq, required this.type, this.text, this.lang, this.isFinal = true});

  /// Reads one entry of `events`.
  factory OryksaPhoneEvent.fromJson(Map<String, dynamic> j) => OryksaPhoneEvent(
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        type: switch ((j['type'] ?? '').toString()) {
          'paired' => OryksaPhoneEventType.paired,
          'listening' => OryksaPhoneEventType.listening,
          'stopped' => OryksaPhoneEventType.stopped,
          'text' => OryksaPhoneEventType.text,
          'phone_left' => OryksaPhoneEventType.phoneLeft,
          'expired' => OryksaPhoneEventType.expired,
          'closed' => OryksaPhoneEventType.closed,
          _ => OryksaPhoneEventType.unknown,
        },
        text: j['text']?.toString(),
        lang: j['lang']?.toString(),
        isFinal: j['final'] != false,
      );

  /// Order of the event.
  final int seq;

  /// Kind.
  final OryksaPhoneEventType type;

  /// For [OryksaPhoneEventType.text]: what the person said.
  final String? text;

  /// For [OryksaPhoneEventType.text]: the language heard.
  final String? lang;

  /// For [OryksaPhoneEventType.text]: the final text (always true for now).
  final bool isFinal;
}

/// One answer of the events long-poll.
@immutable
class OryksaPhoneEventsPage {
  /// Creates a page.
  const OryksaPhoneEventsPage({required this.state, required this.next, this.events = const [], this.phoneConnected});

  /// Reads the answer of `GET /v1/client/tv/pair/{id}/events`.
  factory OryksaPhoneEventsPage.fromJson(Map<String, dynamic> j, {int after = 0}) {
    final events = j['events'] is List
        ? (j['events'] as List).whereType<Map>().map((m) => OryksaPhoneEvent.fromJson(m.cast<String, dynamic>())).toList()
        : <OryksaPhoneEvent>[];
    var next = (j['next'] as num?)?.toInt() ?? after;
    for (final e in events) {
      if (e.seq > next) next = e.seq;
    }
    return OryksaPhoneEventsPage(
      state: (j['state'] ?? 'waiting').toString(),
      next: next,
      events: events,
      phoneConnected: j['phone'] is bool ? j['phone'] as bool : null,
    );
  }

  /// `waiting`, `paired`, `expired` or `closed`.
  final String state;

  /// Whether a phone is connected right now (`phone`), when the server says it.
  final bool? phoneConnected;

  /// Pass as `after` in the next call.
  final int next;

  /// New events, oldest first.
  final List<OryksaPhoneEvent> events;
}
