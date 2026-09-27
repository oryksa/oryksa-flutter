import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'http.dart';
import 'models.dart';

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

  String? _token;
  final Future<String> Function()? _getToken;
  final String _base;
  final http.Client _http;

  /// Time limit for each request.
  final Duration timeout;

  Future<String> _tok(bool force) async {
    if ((_token == null || force) && _getToken != null) {
      _token = await _getToken!();
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

  /// Sends a message. The status is `pending` when the AI needs a few more seconds:
  /// use [sendAndWait] to wait for the text.
  ///
  /// * [appContext]: the screen the customer is on inside your app, so the AI answers about it.
  /// * [voice]: the reply will be heard; it also carries a short [OryksaReply.speech].
  /// * [whisper]: the customer whispered; the spoken reply is shorter and whispered.
  /// * [voiceStats]: audio numbers of this voice turn (sent by the voice screen).
  Future<OryksaReply> send(
    String message, {
    OryksaAppContext? appContext,
    bool voice = false,
    bool whisper = false,
    Map<String, dynamic>? voiceStats,
  }) async =>
      OryksaReply.fromJson(await _req('POST', '/client/chat', {
        'message': message,
        if (appContext != null) 'app_context': appContext.toJson(),
        if (voice) 'voice': true,
        if (whisper) 'whisper': true,
        if (voiceStats != null) ...{'platform': 'flutter', 'voice_stats': voiceStats},
      }));

  /// Sends a message and waits for the reply text (up to [maxWait]).
  Future<String?> sendAndWait(
    String message, {
    Duration maxWait = const Duration(seconds: 40),
    OryksaAppContext? appContext,
  }) async =>
      (await sendAndWaitReply(message, maxWait: maxWait, appContext: appContext)).reply;

  /// Like [sendAndWait], but returns the whole [OryksaReply] (with [OryksaReply.speech] when [voice] is on).
  Future<OryksaReply> sendAndWaitReply(
    String message, {
    Duration maxWait = const Duration(seconds: 40),
    OryksaAppContext? appContext,
    bool voice = false,
    bool whisper = false,
    Map<String, dynamic>? voiceStats,
  }) async {
    final r = await send(message, appContext: appContext, voice: voice, whisper: whisper, voiceStats: voiceStats);
    if (r.status != 'pending') return r;
    final end = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
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
      await _req('POST', '/client/voice-stats', {'platform': 'flutter', 'voice_stats': stats});
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
