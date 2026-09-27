import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/vad.dart';

/// Interromper a ORYKSA enquanto ela fala.
///
/// O dono apanhou isto ao vivo: "ela começou a falar, mas bastou um passarinho
/// pairar ali e ela calou". Eram 250 ms de som acima de um limiar baixo, e um
/// pássaro faz isso sem esforço. Estes testes existem para nunca mais.
void main() {
  /// Um pedaço de 100 ms de som a um dado nível (16 kHz, PCM16).
  /// Com `tom: true` sai periodico, como a voz humana; sem ele sai ruido,
  /// como uma tecla. E o tom que decide se aquilo pode calar a ORYKSA.
  Uint8List pedaco(double nivel, {int ms = 100, bool tom = true}) {
    final n = 16000 * ms ~/ 1000;
    final b = BytesBuilder();
    final r = math.Random(7);
    // Gera a forma da onda e depois ajusta-a para o `nivel` ser exatamente a
    // ENERGIA (rms) pedida. Sem isto, "0,12" no teste dava 0,07 no medidor, e
    // os testes falavam de um numero e a app de outro.
    var fase = 0.0;
    final onda = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      fase += 2 * math.pi * 120 / 16000;
      onda[i] = tom
          ? math.sin(fase) * .8 + math.sin(fase * 2) * .2 + (r.nextDouble() - .5) * .05
          : r.nextDouble() * 2 - 1;
    }
    var energia = 0.0;
    for (final v in onda) {
      energia += v * v;
    }
    final rmsAtual = math.sqrt(energia / n);
    final ganho = rmsAtual > 0 ? nivel / rmsAtual : 0.0;
    for (var i = 0; i < n; i++) {
      final s = ((onda[i] * ganho).clamp(-1.0, 1.0) * 32767).round();
      b.addByte(s & 0xff);
      b.addByte((s >> 8) & 0xff);
    }
    return b.toBytes();
  }

  /// Corre uma sequência (nível, ms) com ela a falar e diz se foi interrompida.
  bool interrompe(List<(double, int)> som, {bool tom = true}) {
    final vad = Vad()..reset();
    for (final (nivel, ms) in som) {
      for (var t = 0; t < ms; t += 100) {
        if (vad.feed(pedaco(nivel, tom: tom), speaking: true).isBargeIn) return true;
      }
    }
    return false;
  }

  test('o passarinho NAO a cala', () {
    // Um chilreio: alto mas curto, e longe do telemovel.
    expect(interrompe([(0.0005, 500), (0.05, 300), (0.0005, 1000)], tom: false), isFalse);
  });

  test('dois chilreios seguidos tambem nao', () {
    expect(
      interrompe([(0.0005, 300), (0.05, 250), (0.0005, 400), (0.05, 250), (0.0005, 600)], tom: false),
      isFalse,
    );
  });

  test('a televisao na sala nao a cala', () {
    // Som continuo mas baixo: fica sempre abaixo do chao da interrupcao.
    expect(interrompe([(0.035, 4000)]), isFalse);
  });

  test('o dono a falar CALA-A', () {
    // Perto do telemovel, alto e seguido: e uma pessoa a interromper.
    expect(interrompe([(0.0005, 200), (0.12, 900)]), isTrue);
  });

  test('o dono a falar com pausas entre silabas cala-a na mesma', () {
    // Entre palavras ha silencio; isso nao pode apagar a conta.
    expect(
      interrompe([(0.12, 300), (0.001, 100), (0.12, 300), (0.001, 100), (0.12, 300)]),
      isTrue,
    );
  });

  test('uma pausa LONGA desiste da interrupcao', () {
    // Dois sons curtos de voz, separados por um segundo de nada. Nenhum deles
    // chega sozinho para contar como palavra, e a pausa apaga o primeiro.
    expect(interrompe([(0.12, 100), (0.0005, 1000), (0.12, 100)]), isFalse);
  });

  test('uma palavra curta de VOZ ja a cala', () {
    // 300 ms com tom: e "para" ou "espera". Tem de a calar logo.
    expect(interrompe([(0.0005, 200), (0.12, 300)]), isTrue);
  });

  test('UM AVIAO a passar nao a cala', () {
    // Alto e seguido durante segundos, mas sem tom: e um motor, nao e ninguem.
    // Apanhado ao vivo: um aviao calou-a e o dono viu. Nunca mais.
    expect(interrompe([(0.0005, 300), (0.18, 5000), (0.0005, 500)], tom: false), isFalse);
  });

  test('um secador, um camiao, uma obra: nada disso a cala', () {
    expect(interrompe([(0.25, 8000)], tom: false), isFalse);
  });

  test('um "shhh" NAO a cala, e e de proposito', () {
    // So voz a interrompe. Um sopro nao tem tom, e deixa-lo passar era abrir a
    // porta ao aviao e ao secador. O dono escolheu: "so se for voz".
    expect(interrompe([(0.0005, 200), (0.18, 900)], tom: false), isFalse);
  });

  test('silencio absoluto nunca a cala', () {
    expect(interrompe([(0.0, 5000)]), isFalse);
  });

  test('ESCREVER NO TECLADO nao a cala', () {
    // O dono apanhou isto: estava a ouvi-la, escreveu no MacBook, e ela calou.
    // Uma tecla e um estalo de 40 ms; cinco por segundo, com 160 ms de nada
    // pelo meio. Some muito tempo, mas nunca ha som SEGUIDO que chegue.
    final teclas = <(double, int)>[];
    for (var i = 0; i < 30; i++) {
      teclas.add((0.18, 40));
      teclas.add((0.0008, 160));
    }
    expect(interrompe(teclas, tom: false), isFalse);
  });

  test('escrever DEPRESSA tambem nao a cala', () {
    final teclas = <(double, int)>[];
    for (var i = 0; i < 40; i++) {
      teclas.add((0.2, 60));
      teclas.add((0.001, 60));
    }
    expect(interrompe(teclas, tom: false), isFalse);
  });

  test('bater na mesa (um toque seco) nao a cala', () {
    expect(interrompe([(0.0008, 300), (0.3, 80), (0.0008, 2000)], tom: false), isFalse);
  });

  test('a propria voz dela a escapar do altifalante nao a cala', () {
    // MEDIDO AO VIVO: o eco dela entra a 0,05 e tem tom 0,86 (e voz, e a voz
    // dela). Isto era o que a fazia calar-se sozinha a meio da frase, sem
    // ninguem fazer barulho nenhum. Por mais tempo que dure, nao pode contar.
    expect(interrompe([(0.05, 8000)]), isFalse);
  });

  test('o eco dela um pouco mais alto tambem nao a cala', () {
    expect(interrompe([(0.07, 6000)]), isFalse);
  });

  test('com muito eco a escapar, e preciso falar mais alto (mas da)', () {
    final vad = Vad()..reset();
    // Primeiro um bom bocado do eco dela.
    for (var t = 0; t < 2000; t += 100) {
      vad.feed(pedaco(0.05), speaking: true);
    }
    // Agora o dono, ao pe do telemovel: tem de a calar.
    var cortou = false;
    for (var t = 0; t < 900; t += 100) {
      if (vad.feed(pedaco(0.25), speaking: true).isBargeIn) cortou = true;
    }
    expect(cortou, isTrue);
  });
}
