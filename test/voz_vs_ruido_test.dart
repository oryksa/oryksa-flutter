import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/vad.dart';

/// So a VOZ dele a pode calar. Nem teclas, nem palmas, nem portas.
///
/// Regra do dono, nas palavras dele: "não quero que ruídos interrompam ela,
/// só a minha voz". E do outro lado: "mandei ela calar e ela não calou" -
/// uma palavra curta como "para" tem de chegar.
void main() {
  Uint8List wav(String n) {
    final all = File('test/$n').readAsBytesSync();
    return Uint8List.fromList(all.sublist(44));
  }

  List<Uint8List> pedacos(Uint8List pcm, {int size = 2048}) {
    final out = <Uint8List>[];
    for (var i = 0; i < pcm.length; i += size) {
      out.add(Uint8List.sublistView(pcm, i, (i + size).clamp(0, pcm.length)));
    }
    return out;
  }

  /// O tom MAIS ALTO que este som atinge.
  ///
  /// E o maximo que interessa, nao a media: numa palavra como "Para" quase tudo
  /// e o "p" (um estalo sem tom) e so a vogal tem voz. Se se olhasse para a
  /// media, a palavra "Para" contava como ruido e ela nao obedecia a quem lhe
  /// manda calar.
  double tomMaximo(String ficheiro) {
    final cs = pedacos(wav(ficheiro)).where((c) => Vad.rmsOf(c) > 0.02).toList();
    if (cs.isEmpty) return 0;
    return cs.map(Vad.periodicidade).reduce((a, b) => a > b ? a : b);
  }

  bool cala(String ficheiro) {
    final vad = Vad()..reset();
    for (final c in pedacos(wav(ficheiro))) {
      if (vad.feed(c, speaking: true).isBargeIn) return true;
    }
    return false;
  }

  test('a voz humana TEM tom; o teclado nao tem', () {
    // Medido: teclado nunca passa de 0,20; a voz chega a 0,50 e 0,93.
    for (final v in ['para.wav', 'espera.wav', 'curta.wav', 'pausas.wav']) {
      expect(tomMaximo(v), greaterThan(Vad.bargeVozMin), reason: '$v deu tom ${tomMaximo(v)}');
    }
    expect(tomMaximo('teclado.wav'), lessThan(Vad.bargeVozMin),
        reason: 'as teclas deram tom ${tomMaximo('teclado.wav')}');
  });

  test('uma palavra curta ("Para") CALA-A', () {
    expect(cala('para.wav'), isTrue);
  });

  test('"Espera" tambem a cala', () {
    expect(cala('espera.wav'), isTrue);
  });

  test('digitar nao a cala, por muito que se escreva', () {
    expect(cala('teclado.wav'), isFalse);
  });
}
