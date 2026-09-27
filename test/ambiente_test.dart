import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/vad.dart';

/// Ela nunca pode ficar surda, nem se calar com o que nao e voz.
///
/// Os dois lados da mesma moeda, e o dono apanhou os dois ao vivo:
/// "um aviao a passar interrompeu ela" e "nao deixa ela ficar calada em
/// ambiente ruidoso".
void main() {
  Uint8List som(double rms, {int ms = 100, bool tom = true, int hz = 120}) {
    final n = 16000 * ms ~/ 1000;
    final r = math.Random(5);
    final onda = List<double>.filled(n, 0);
    var fase = 0.0;
    for (var i = 0; i < n; i++) {
      fase += 2 * math.pi * hz / 16000;
      onda[i] = tom
          ? math.sin(fase) * .8 + math.sin(fase * 2) * .2 + (r.nextDouble() - .5) * .05
          : r.nextDouble() * 2 - 1;
    }
    var e = 0.0;
    for (final v in onda) {
      e += v * v;
    }
    final g = e > 0 ? rms / math.sqrt(e / n) : 0.0;
    final b = BytesBuilder();
    for (var i = 0; i < n; i++) {
      final s = ((onda[i] * g).clamp(-1.0, 1.0) * 32767).round();
      b.addByte(s & 0xff);
      b.addByte((s >> 8) & 0xff);
    }
    return b.toBytes();
  }

  test('num cafe barulhento ela CONTINUA a ouvir o dono', () {
    final vad = Vad()..reset();
    // Dois segundos de barulho de fundo forte, para o ruido de referencia subir.
    for (var t = 0; t < 2000; t += 100) {
      vad.feed(som(0.055, tom: false));
    }
    // Agora o dono fala ao pe do telemovel, como sempre faz.
    var ouviu = false;
    for (var t = 0; t < 1500; t += 100) {
      if (vad.feed(som(0.15)).isCapturing) ouviu = true;
    }
    expect(ouviu, isTrue, reason: 'ficou surda com o barulho a volta');
  });

  test('a fasquia de ouvir nunca passa do teto', () {
    expect(Vad.tetoOuvir, lessThanOrEqualTo(0.12));
  });

  test('o chao de interromper fica acima do eco dela e abaixo da voz', () {
    // Eco medido ao vivo: 0,054. Voz do dono ao pe do telemovel: 0,12 a 0,25.
    expect(Vad.bargeFloor, greaterThan(0.06));
    expect(Vad.bargeFloor, lessThan(0.12));
  });
}
