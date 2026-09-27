import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/vad.dart';

/// Testa a deteção de fala com SOM A SÉRIO (`test/fala.wav`, uma frase gravada).
///
/// Existe porque a app andou a cortar o dono ao fim de 100 ms e a mandar clipes
/// que o servidor não conseguia transcrever. Nos registos do telemóvel dele via-se
/// `voice_too_short spokeMs=100` dezenas de vezes.
void main() {
  /// Lê o WAV e devolve só as amostras (salta o cabeçalho de 44 bytes).
  Uint8List samples() {
    final f = File('test/fala.wav');
    final all = f.readAsBytesSync();
    return Uint8List.fromList(all.sublist(44));
  }

  /// Parte o som em pedaços do tamanho que o microfone entrega (2048 bytes).
  List<Uint8List> chunks(Uint8List pcm, {int size = 2048}) {
    final out = <Uint8List>[];
    for (var i = 0; i < pcm.length; i += size) {
      out.add(Uint8List.sublistView(pcm, i, (i + size).clamp(0, pcm.length)));
    }
    return out;
  }

  /// Silêncio, para simular a pausa depois da frase.
  Uint8List silence({int ms = 2000, int rate = 16000}) => Uint8List(rate * 2 * ms ~/ 1000);

  test('uma frase falada e reconhecida como fala e enviada', () {
    final vad = Vad();
    final all = [...chunks(samples()), ...chunks(silence())];
    VadStep? end;
    for (final c in all) {
      final r = vad.feed(c);
      if (r.isDone) {
        end = r;
        break;
      }
    }
    expect(end, isNotNull, reason: 'nunca fechou a frase: ficaria a ouvir para sempre');
    expect(end!.enough, isTrue, reason: 'a frase foi descartada como "too short" - era este o bug');
    expect(end.spokeMs, greaterThan(Vad.minSpeechMs));
    // ignore: avoid_print
    print('fala detetada: ${end.spokeMs} ms');
  });

  test('so ruido de fundo nao e enviado', () {
    final vad = Vad();
    // ruído baixo e constante, como o chiar de uma sala
    final noise = Uint8List(2048);
    for (var i = 0; i < noise.length; i += 2) {
      noise[i] = 12;
      noise[i + 1] = 0;
    }
    VadStep? end;
    for (var k = 0; k < 200; k++) {
      final r = vad.feed(noise);
      if (r.isDone) {
        end = r;
        break;
      }
    }
    expect(end?.enough ?? false, isFalse, reason: 'ruído não pode ir para o servidor');
  });

  test('uma pausa curta no meio da frase nao fecha a captura', () {
    final vad = Vad();
    final fala = chunks(samples());
    // fala, pausa de meio segundo, fala outra vez
    final all = [...fala.take(20), ...chunks(silence(ms: 500)), ...fala.skip(20)];
    var closedEarly = false;
    for (final c in all.take(fala.take(20).length + chunks(silence(ms: 500)).length + 5)) {
      if (vad.feed(c).isDone) {
        closedEarly = true;
        break;
      }
    }
    expect(closedEarly, isFalse, reason: 'cortava a meio da frase e mandava um clipe inútil');
  });
}
