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
  Future<OryksaReply> send(String message) async =>
      OryksaReply.fromJson(await _req('POST', '/client/chat', {'message': message}));

  /// Sends a message and waits for the reply text (up to [maxWait]).
  Future<String?> sendAndWait(String message, {Duration maxWait = const Duration(seconds: 40)}) async {
    var r = await send(message);
    if (r.status != 'pending') return r.reply;
    final end = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final hist = await messages();
      if (hist.isNotEmpty && hist.last.role == 'assistant') return hist.last.content;
    }
    return r.reply;
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
