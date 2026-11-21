import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'http.dart';
import 'models.dart';
import 'platform.dart';

/// In-app client. Uses a short-lived session token (`oryk_cs_...`) created by YOUR
/// server with `POST /v1/sessions`. The secret API key never goes into the app.
///
/// Pass [getToken] so the client can ask your server for a new token when the
/// current one expires.
class OryksaClient {
  /// Creates the client with a [token], a [getToken] callback, or both.
  OryksaClient({
    String? token,
    Future<String> Function()? getToken,
    String baseUrl = oryksaDefaultBase,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  })  : _token = token,
        _getToken = getToken,
        _base = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _http = httpClient ?? http.Client() {
    if (token == null && getToken == null) {
      throw ArgumentError('OryksaClient needs a token or getToken.');
    }
    if (token != null && token.startsWith('oryk_live_')) {
      throw ArgumentError('Never use the secret API key in an app. Use a session token (oryk_cs_...).');
    }
  }

  /// For apps WITHOUT a server of their own: the client takes its session token from the
  /// business's PUBLIC chat token (ORYKSA > Connectors > Website chat, the same token the
  /// website chat uses). No secret key is involved, and the conversation is kept apart from
  /// the ones your server creates. Pass a random [conversationId] saved on the device
  /// (a UUID) to keep the history between app launches.
  ///
  /// When the business limits the chat to its own domains, use [OryksaClient.new] with a
  /// token from your server instead.
  factory OryksaClient.public({
    required String chatToken,
    String? conversationId,
    String? customerName,
    String baseUrl = oryksaDefaultBase,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final hc = httpClient ?? http.Client();
    final conv = conversationId ?? _randomId();
    Future<String> fetch() async {
      final r = await hc
          .post(Uri.parse('$base/public/sessions'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'widget_token': chatToken,
                'conversation_id': conv,
                if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
              }))
          .timeout(timeout);
      Map<String, dynamic> j = const {};
      try {
        j = (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
      } catch (_) {}
      final t = j['client_token'];
      if (r.statusCode != 201 || t is! String || t.isEmpty) {
        final e = (j['error'] is Map) ? (j['error'] as Map) : const {};
        throw OryksaException(r.statusCode, (e['code'] ?? 'public_session_failed').toString(),
            (e['message'] ?? 'Could not open the chat.').toString());
      }
      return t;
    }

    return OryksaClient(getToken: fetch, baseUrl: base, httpClient: hc, timeout: timeout);
  }

  static String _randomId() {
    final r = Random.secure();
    return List.generate(24, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
  }

  String? _token;
  final Future<String> Function()? _getToken;
  final String _base;
  final http.Client _http;

  /// Time limit for each request.
  final Duration timeout;

  Future<String> _tok(bool force) async {
    if ((_token == null || force) && _getToken != null) {
      _token = await _getToken();
    }
    final t = _token;
    if (t == null || t.isEmpty) {
      throw const OryksaException(401, 'no_token', 'No session token.');
    }
    return t;
  }

  Future<Map<String, dynamic>> _req(String method, String path, [Object? body]) async {
    try {
      return await oryksaRequest(_http, _base, await _tok(false), method, path, body: body, timeout: timeout);
    } on OryksaException catch (e) {
      if ((e.code == 'session_expired' || e.status == 401) && _getToken != null) {
        return oryksaRequest(_http, _base, await _tok(true), method, path, body: body, timeout: timeout);
      }
      rethrow;
    }
  }

  /// Name, photo, greeting and suggestions of the AI employee.
  Future<OryksaAgent> agent() async => OryksaAgent.fromJson(await _req('GET', '/client/agent'));

  final Map<String, OryksaLinkPreview> _previews = {};

  /// Title and picture of a link the AI gave, for the card under her reply. Only the pages
  /// of the business's own site (its website chat domains) get a title and a picture.
  /// Null when it cannot be read; never throws.
  Future<OryksaLinkPreview?> linkPreview(String url) async {
    final hit = _previews[url];
    if (hit != null) return hit;
    try {
      final p = OryksaLinkPreview.fromJson(await _req('GET', '/client/link-preview?url=${Uri.encodeQueryComponent(url)}'));
      if (_previews.length > 200) _previews.clear();
      _previews[url] = p;
      return p;
    } catch (_) {
      return null;
    }
  }

  /// Sends a message ([image]: a photo from the customer, the AI looks at it). The status is
  /// `pending` when the AI needs a few more seconds:
  /// use [sendAndWait] to wait for the text.
  ///
  /// * [appContext]: the screen the customer is on inside your app, so the AI answers about it.
  /// * [voice]: the reply will be heard; it also carries a short [OryksaReply.speech].
  /// * [whisper]: the customer whispered; the spoken reply is shorter and whispered.
  /// * [voiceStats]: audio numbers of this voice turn (sent by the voice screen).
  /// * [lang]: the language of your app screen (`en`, `pt`, `br`, `es`). The AI uses
  ///   it when the message alone does not show the language (for example "ok").
  Future<OryksaReply> send(
    String message, {
    OryksaAppContext? appContext,
    bool voice = false,
    bool whisper = false,
    Map<String, dynamic>? voiceStats,
    String? lang,
    OryksaImage? image,
  }) async =>
      OryksaReply.fromJson(await _req('POST', '/client/chat', {
        'message': message,
        // O aparelho vai em TODOS os pedidos, nao so nos que levam numeros da voz:
        // e com ele que o aviso de lead do dono diz "na tua app (iPhone)" ou "(Android)".
        'platform': oryksaPlatform,
        if (image != null) ...{'image_base64': base64Encode(image.bytes), 'image_mime': image.mime},
        if (lang != null && lang.isNotEmpty) 'lang': lang,
        if (appContext != null) 'app_context': appContext.toJson(),
        if (voice) 'voice': true,
        if (whisper) 'whisper': true,
        if (voiceStats != null) 'voice_stats': voiceStats,
      }));

  /// Sends a message and waits for the reply text (up to [maxWait]).
  Future<String?> sendAndWait(
    String message, {
    Duration maxWait = const Duration(seconds: 40),
    OryksaAppContext? appContext,
    String? lang,
    OryksaImage? image,
  }) async =>
      (await sendAndWaitReply(message, maxWait: maxWait, appContext: appContext, lang: lang, image: image)).reply;

  /// Like [sendAndWait], but returns the whole [OryksaReply] (with [OryksaReply.speech] when [voice] is on).
  Future<OryksaReply> sendAndWaitReply(
    String message, {
    Duration maxWait = const Duration(seconds: 40),
    OryksaAppContext? appContext,
    bool voice = false,
    bool whisper = false,
    Map<String, dynamic>? voiceStats,
    String? lang,
    OryksaImage? image,
  }) async {
    final r = await send(message,
        appContext: appContext, voice: voice, whisper: whisper, voiceStats: voiceStats, lang: lang, image: image);
    if (r.status != 'pending') return r;
    final end = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final hist = await messages();
      if (hist.isNotEmpty && hist.last.role == 'assistant') {
        return OryksaReply(status: 'replied', reply: hist.last.content, conversationId: r.conversationId, whisper: whisper);
      }
    }
    return r;
  }

  /// The AI's voice (ElevenLabs, the voice chosen in ORYKSA) for one reply of this
  /// conversation, as MP3 bytes. Returns null when the voice is not available: then
  /// show the text only (never a robot voice).
  Future<Uint8List?> tts(String text, {bool whisper = false}) async {
    try {
      try {
        return await oryksaBytes(_http, _base, await _tok(false), '/client/tts', {'text': text, if (whisper) 'whisper': true},
            timeout: timeout);
      } on OryksaException catch (e) {
        if ((e.code == 'session_expired' || e.status == 401) && _getToken != null) {
          return await oryksaBytes(_http, _base, await _tok(true), '/client/tts', {'text': text, if (whisper) 'whisper': true},
              timeout: timeout);
        }
        rethrow;
      }
    } catch (_) {
      return null;
    }
  }

  /// Turns the customer's voice into text. [wav] is 16 kHz mono PCM16 WAV, up to 15 seconds.
  /// Returns `''` when nothing was said and null when it failed.
  Future<String?> transcribe(Uint8List wav) async {
    try {
      Map<String, dynamic> d;
      try {
        d = await oryksaUpload(_http, _base, await _tok(false), '/client/transcribe', wav, 'voice.wav', 'audio/wav',
            timeout: timeout);
      } on OryksaException catch (e) {
        if ((e.code == 'session_expired' || e.status == 401) && _getToken != null) {
          d = await oryksaUpload(_http, _base, await _tok(true), '/client/transcribe', wav, 'voice.wav', 'audio/wav',
              timeout: timeout);
        } else {
          rethrow;
        }
      }
      return (d['text'] ?? '').toString().trim();
    } catch (_) {
      return null;
    }
  }

  /// Reports a voice turn that produced no message (nothing heard, a cut with nothing said).
  Future<void> voiceStats(Map<String, dynamic> stats) async {
    try {
      await _req('POST', '/client/voice-stats', {'platform': oryksaPlatform, 'voice_stats': stats});
    } catch (_) {}
  }

  /// Messages of this conversation.
  Future<List<OryksaMessage>> messages() async {
    final d = await _req('GET', '/client/messages');
    final list = d['messages'];
    return list is List
        ? list.whereType<Map>().map((m) => OryksaMessage.fromJson(Map<String, dynamic>.from(m))).toList()
        : <OryksaMessage>[];
  }

  /// Closes the underlying HTTP client.
  void close() => _http.close();
}
