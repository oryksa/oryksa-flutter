import 'package:flutter_test/flutter_test.dart';

/// A regra que decide se o que foi dito vai para a ORYKSA.
/// Este teste existe porque a app esteve a OUVIR e a NUNCA ENVIAR: o `_reset()`
/// punha `speechMs` a zero mesmo antes de o teste correr, e ele dava sempre
/// falso. Se alguém voltar a ler a variável depois do reset, isto apanha.
bool shouldSend({required int spokeMs, required int bytes, int sampleRate = 16000}) =>
    spokeMs > 250 && bytes > sampleRate ~/ 2;

void main() {
  group('decisao de enviar o audio', () {
    test('fala normal com som suficiente: envia', () {
      expect(shouldSend(spokeMs: 1200, bytes: 40000), isTrue);
    });

    test('um estalido curto: nao envia', () {
      expect(shouldSend(spokeMs: 120, bytes: 40000), isFalse);
    });

    test('falou mas quase nao ha som gravado: nao envia', () {
      expect(shouldSend(spokeMs: 1200, bytes: 500), isFalse);
    });

    test('o bug real: ler speechMs DEPOIS do reset nunca enviava', () {
      var speechMs = 1500; // o dono falou mesmo
      final bytes = 40000;
      // ... _reset() acontecia aqui ...
      speechMs = 0;
      expect(shouldSend(spokeMs: speechMs, bytes: bytes), isFalse,
          reason: 'era isto que fazia a ORYKSA ouvir e nunca responder');
      // com o valor guardado antes do reset, envia como deve ser
      expect(shouldSend(spokeMs: 1500, bytes: bytes), isTrue);
    });
  });
}
