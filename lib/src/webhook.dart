import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors.dart';

/// Verifies an ORYKSA webhook (for Dart backends). Pass the RAW body and the
/// `ORYKSA-Signature` header. Returns the parsed event or throws [OryksaException].
Map<String, dynamic> verifyWebhook(
  String rawBody,
  String? signatureHeader,
  String secret, {
  Duration tolerance = const Duration(minutes: 5),
}) {
  final parts = <String, String>{};
  for (final p in (signatureHeader ?? '').split(',')) {
    final i = p.indexOf('=');
    if (i > 0) parts[p.substring(0, i).trim()] = p.substring(i + 1).trim();
  }
  final t = int.tryParse(parts['t'] ?? '') ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  if (t == 0 || (now - t).abs() > tolerance.inSeconds) {
    throw const OryksaException(400, 'invalid_signature', 'Webhook timestamp is missing or too old.');
  }
  final expected = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$rawBody')).toString();
  final got = parts['v1'] ?? '';
  var diff = expected.length ^ got.length;
  for (var i = 0; i < expected.length && i < got.length; i++) {
    diff |= expected.codeUnitAt(i) ^ got.codeUnitAt(i);
  }
  if (diff != 0) {
    throw const OryksaException(400, 'invalid_signature', 'Webhook signature does not match.');
  }
  final d = jsonDecode(rawBody);
  return d is Map<String, dynamic> ? d : <String, dynamic>{'data': d};
}
