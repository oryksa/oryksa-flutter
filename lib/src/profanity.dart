import 'dart:convert';

import 'package:http/http.dart' as http;

/// Masks swear words the customer types (owner rule: every ORYKSA chat shows them as asterisks).
///
/// One list for all ORYKSA clients, from `GET https://app.oryksa.com/widget/profanity.json?lang=`
/// (kept 24 hours). The AI's replies already come filtered from the server.
class OryksaProfanity {
  OryksaProfanity._();

  static const _url = 'https://app.oryksa.com/widget/profanity.json';
  static final Map<String, RegExp> _re = {};
  static final Map<String, DateTime> _at = {};

  /// Language key used by the list: `pt`, `br`, `en` or `es`.
  static String key(String lang) => lang.contains('br') ? 'br' : (lang.length >= 2 ? lang.substring(0, 2) : 'en');

  /// Loads (or refreshes after 24 h) the list for [lang]. Never throws.
  static Future<void> load(String lang, {http.Client? client}) async {
    final k = key(lang);
    final at = _at[k];
    if (at != null && DateTime.now().difference(at) < const Duration(hours: 24)) return;
    try {
      final c = client ?? http.Client();
      final r = await c.get(Uri.parse('$_url?lang=$k'));
      if (client == null) c.close();
      if (r.statusCode != 200) return;
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is! Map || d['pattern'] is! String) return;
      final flags = (d['flags'] ?? '').toString();
      _re[k] = RegExp(d['pattern'] as String, caseSensitive: !flags.contains('i'), unicode: true);
      _at[k] = DateTime.now();
    } catch (_) {}
  }

  /// Uses a pattern directly (tests, or your own copy of the list).
  static void use(String lang, String pattern, {String flags = 'giu'}) {
    final k = key(lang);
    _re[k] = RegExp(pattern, caseSensitive: !flags.contains('i'), unicode: true);
    _at[k] = DateTime.now();
  }

  /// [text] with the swear words replaced by asterisks (at least 3). Unchanged when the list is not loaded.
  static String mask(String text, String lang) {
    final re = _re[key(lang)];
    if (re == null || text.isEmpty) return text;
    return text.replaceAllMapped(re, (m) {
      final pre = m.group(1) ?? '';
      final word = m.group(0)!.substring(pre.length).replaceAll(RegExp(r'\s'), '');
      return pre + '*' * (word.length < 3 ? 3 : word.length);
    });
  }
}
