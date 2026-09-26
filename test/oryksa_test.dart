import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/oryksa.dart';

void main() {
  test('agent picks the language with fallbacks', () {
    final a = OryksaAgent.fromJson({
      'name': 'ORYKSA',
      'avatar': 'https://x/a.jpg',
      'greeting': {'en': 'Hi', 'pt': 'Olá'},
      'suggestions': {'en': ['Prices?']},
    });
    expect(OryksaAgent.pick(a.greeting, 'br'), 'Olá');
    expect(OryksaAgent.pick(a.greeting, 'es'), 'Hi');
    expect(OryksaAgent.pick(a.suggestions, 'pt'), ['Prices?']);
  });

  test('the secret key is refused in the app client', () {
    expect(() => OryksaClient(token: 'oryk_live_abc'), throwsArgumentError);
    expect(() => OryksaClient(), throwsArgumentError);
  });

  test('webhook signature', () {
    const secret = 'whsec_test';
    final body = jsonEncode({'type': 'message.replied'});
    final t = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$body')).toString();
    expect(verifyWebhook(body, 't=$t,v1=$sig', secret)['type'], 'message.replied');
    expect(() => verifyWebhook(body, 't=$t,v1=00', secret), throwsA(isA<OryksaException>()));
  });
}
