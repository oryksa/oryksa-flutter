import 'package:http/http.dart' as http;

import 'http.dart';
import 'models.dart';

/// Server client for Dart backends (shelf, dart_frog, serverpod...). Uses the SECRET
/// API key (`oryk_live_...`). Never put the key inside a Flutter app: in the app use
/// [OryksaClient] with a session token created here with [createSession].
class Oryksa {
  /// Creates the server client.
  Oryksa(
    String apiKey, {
    String baseUrl = oryksaDefaultBase,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  })  : _key = apiKey,
        _base = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _http = httpClient ?? http.Client() {
    if (!apiKey.startsWith('oryk_live_')) {
      throw ArgumentError('An ORYKSA API key (oryk_live_...) is required. Create one at developer.oryksa.com.');
    }
  }

  final String _key;
  final String _base;
  final http.Client _http;

  /// Time limit for each request.
  final Duration timeout;

  Future<Map<String, dynamic>> _req(String method, String path, [Object? body]) =>
      oryksaRequest(_http, _base, _key, method, path, body: body, timeout: timeout);

  /// Account, plan and usage.
  Future<Map<String, dynamic>> account() => _req('GET', '/account');

  /// Chat with the AI employee. Reuse [conversationId] to keep the context.
  Future<OryksaReply> chat(String message, {String? conversationId, String? customerName}) async =>
      OryksaReply.fromJson(await _req('POST', '/chat', {
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        if (customerName != null) 'customer_name': customerName,
      }));

  /// Short-lived token for one app user. Send only `client_token` to the app.
  Future<Map<String, dynamic>> createSession({String? conversationId, String? customerName, int ttlMinutes = 60}) =>
      _req('POST', '/sessions', {
        if (conversationId != null) 'conversation_id': conversationId,
        if (customerName != null) 'customer_name': customerName,
        'ttl_minutes': ttlMinutes,
      });

  /// Replace the app pages the AI knows (Brain).
  Future<Map<String, dynamic>> setPages(List<Map<String, String>> pages, {String? businessSummary, String? siteUrl}) =>
      _req('PUT', '/knowledge/pages', {
        'pages': pages,
        if (businessSummary != null) 'business_summary': businessSummary,
        if (siteUrl != null) 'site_url': siteUrl,
      });

  /// Add questions and answers to the Brain.
  Future<Map<String, dynamic>> addFaq(List<Map<String, String>> items) => _req('POST', '/knowledge/faq', {'items': items});

  /// Update the AI employee profile (name, business, languages...).
  Future<Map<String, dynamic>> updateAgent(Map<String, dynamic> fields) => _req('PATCH', '/agent', fields);

  /// Teach the AI employee about your app: what it is, its screens, settings and FAQ.
  /// Call it on every release so the Brain stays in sync with the app.
  Future<Map<String, dynamic>> learnApp({
    required String name,
    String? description,
    String? url,
    String? agentName,
    List<String>? languages,
    List<Map<String, String>> screens = const [],
    Map<String, Object?> settings = const {},
    List<Map<String, String>> faq = const [],
  }) async {
    final out = <String, dynamic>{};
    out['agent'] = await updateAgent({
      'business_name': name,
      if (description != null) 'business_description': description,
      if (agentName != null) 'agent_name': agentName,
      if (languages != null) 'languages': languages,
    });
    final pages = <Map<String, String>>[
      if (description != null) {'title': '$name - overview', 'content': description},
      for (final s in screens)
        if ((s['content'] ?? '').isNotEmpty)
          {'title': s['title'] ?? 'Screen', 'content': s['content']!, if (s['url'] != null) 'url': s['url']!},
      if (settings.isNotEmpty)
        {'title': '$name - configuration', 'content': settings.entries.map((e) => '${e.key}: ${e.value}').join('\n')},
    ];
    if (pages.isNotEmpty) out['pages'] = await setPages(pages, siteUrl: url);
    if (faq.isNotEmpty) out['faq'] = await addFaq(faq);
    return out;
  }

  /// Closes the underlying HTTP client.
  void close() => _http.close();
}
