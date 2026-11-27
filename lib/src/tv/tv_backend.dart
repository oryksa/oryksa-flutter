import '../client.dart';
import '../errors.dart';
import '../models.dart';
import 'tv_models.dart';

/// What the TV pieces need from ORYKSA. The real one is [OryksaTvClientBackend]; tests and
/// demos use [OryksaTvFakeBackend]. Your app never changes when one is swapped for the other.
abstract class OryksaTvBackend {
  /// The value sent as `platform` (for example `fire_tv`).
  String get platform;

  /// The TV configuration for [locale] (texts, presenter, rules). The server picks the
  /// supported locale and says which in [OryksaTvConfig.locale].
  Future<OryksaTvConfig> config(String locale);

  /// The presenter's line [text] in [locale], charged each time by the ORYKSA interaction cost
  /// table ([OryksaTvSpeech.interactionsSpent]; a line not counted is not shown). [voice] `false`:
  /// subtitles only, no voice wanted. [cachedRev]: the device already has this line with that
  /// voice revision, so the server may only count it and send no voice. The bytes may be empty
  /// (subtitles only). Null when the server gave nothing for it. Throws on other errors.
  Future<OryksaTvSpeech?> speak(String text, {required String locale, bool whisper = false, bool voice = true, String? cachedRev});

  /// Sends a message to the AI and waits for the reply (the assistant panel).
  Future<OryksaReply> chat(String message, {required String locale, OryksaAppContext? appContext, bool voice = false});

  /// An AI task of your app (`client.ai`), counted as ORYKSA interactions.
  Future<OryksaAiResult> ai({String? instructions, String? input, Map<String, dynamic>? schema});

  /// Starts pairing a phone: the QR and the code to show.
  Future<OryksaPairing> pair(String locale);

  /// Waits up to [wait] for phone events newer than [after] (long-poll).
  Future<OryksaPhoneEventsPage> phoneEvents(String pairId, {int after = 0, Duration wait = const Duration(seconds: 25)});

  /// Ends the pairing.
  Future<void> unpair(String pairId);
}

/// The real backend: the ORYKSA API through an [OryksaClient] (its session token, its
/// `platform`). Written against the contract in the TV SDK design (section 9); each call is
/// only proven once the server side is live.
class OryksaTvClientBackend implements OryksaTvBackend {
  /// Creates the backend on [client]. Create the client with the TV `platform`, for
  /// example `OryksaClient(getToken: ..., platform: OryksaTvPlatform.fireTv.wire)`.
  OryksaTvClientBackend(this.client);

  /// The client with the session token.
  final OryksaClient client;

  @override
  String get platform => client.platform;

  String _q(String v) => Uri.encodeQueryComponent(v);
  String _p(String v) => Uri.encodeComponent(v);

  @override
  Future<OryksaTvConfig> config(String locale) async {
    final l = oryksaTvNormalizeLocale(locale);
    final j = await client.request('GET', '/client/agent${l.isEmpty ? '' : '?locale=${_q(l)}'}');
    return OryksaTvConfig.fromAgentJson(j, requestedLocale: l);
  }

  @override
  Future<OryksaTvSpeech?> speak(String text, {required String locale, bool whisper = false, bool voice = true, String? cachedRev}) async {
    final l = oryksaTvNormalizeLocale(locale);
    try {
      final a = await client.requestAudio('/client/tts', {
        'text': text,
        if (l.isNotEmpty) 'locale': l,
        'purpose': 'presenter',
        'platform': platform,
        if (whisper) 'whisper': true,
        // Subtitles only: the server counts the line and sends no voice.
        if (!voice) 'voice': false,
        // The device has this line with this voice: the server counts it and need not make the voice again.
        if (voice && cachedRev != null && cachedRev.isNotEmpty) ...{'cached': true, 'voice_rev': cachedRev},
      });
      return OryksaTvSpeech(
        a.bytes,
        locale: a.header('x-oryksa-locale') ?? l,
        voiceRev: a.header('x-oryksa-voice-rev'),
        interactionsSpent: int.tryParse(a.header('x-oryksa-interactions-spent') ?? ''),
      );
    } on OryksaException catch (e) {
      if (e.code == 'voice_unavailable') return null;
      rethrow;
    }
  }

  @override
  Future<OryksaReply> chat(String message, {required String locale, OryksaAppContext? appContext, bool voice = false}) {
    final lang = oryksaTvChatLang(locale);
    return client.sendAndWaitReply(message, appContext: appContext, voice: voice, lang: lang.isEmpty ? null : lang);
  }

  @override
  Future<OryksaAiResult> ai({String? instructions, String? input, Map<String, dynamic>? schema}) =>
      client.ai(instructions: instructions, input: input, schema: schema);

  @override
  Future<OryksaPairing> pair(String locale) async {
    final l = oryksaTvNormalizeLocale(locale);
    return OryksaPairing.fromJson(await client.request('POST', '/client/tv/pair', {
      if (l.isNotEmpty) 'locale': l,
      'platform': platform,
    }));
  }

  @override
  Future<OryksaPhoneEventsPage> phoneEvents(String pairId, {int after = 0, Duration wait = const Duration(seconds: 25)}) async {
    // The server holds the request for up to `wait` (at most 30 s): keep it well under the
    // client's time limit too.
    var secs = wait.inSeconds;
    final limit = client.timeout.inSeconds - 5;
    if (secs > limit) secs = limit;
    if (secs > 30) secs = 30;
    if (secs < 1) secs = 1;
    final j = await client.request('GET', '/client/tv/pair/${_p(pairId)}/events?after=$after&wait=$secs');
    return OryksaPhoneEventsPage.fromJson(j, after: after);
  }

  @override
  Future<void> unpair(String pairId) async {
    await client.request('DELETE', '/client/tv/pair/${_p(pairId)}');
  }
}
