import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/oryksa.dart';

/// The swear word list of the server (profanity_br.json is a copy of GET /widget/profanity.json?lang=br).
void main() {
  final spec = jsonDecode(File('test/profanity_br.json').readAsStringSync()) as Map<String, dynamic>;
  OryksaProfanity.use('br', spec['pattern'] as String, flags: spec['flags'] as String);

  test('swear words the customer types show as asterisks', () {
    expect(OryksaProfanity.mask('filha da puta', 'br'), 'filha da ****');
    expect(OryksaProfanity.mask('vai tomar no cu', 'br'), 'vai tomar ****'); // the list masks the whole expression "no cu"
    expect(OryksaProfanity.mask('Que PORRA é essa?', 'br'), 'Que ***** é essa?');
  });

  test('normal words stay as they are', () {
    for (final t in ['Quero uma vela de lavanda.', 'O curso de computador custa quanto?', 'Cuidado com a entrega', 'Olá, boa tarde!']) {
      expect(OryksaProfanity.mask(t, 'br'), t);
    }
  });

  test('without the list nothing changes', () {
    expect(OryksaProfanity.mask('filha da puta', 'es'), 'filha da puta');
  });
}
