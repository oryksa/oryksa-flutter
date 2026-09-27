import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/vad.dart';

/// Quanto silêncio é preciso para ela perceber que a frase acabou.
///
/// Este número já custou dias ao dono: a 450 ms cortava-lhe a frase a meio e
/// o Whisper recebia clipes de 100 ms. Subiu para 900 ms e passou a funcionar,
/// mas 900 ms é muito tempo à espera numa conversa falada.
///
/// Estes testes usam FALA A SÉRIO, com as pausas que qualquer pessoa faz entre
/// palavras, para se poder baixar o número sem voltar a partir tudo.
void main() {
  Uint8List wav(String nome) {
    final all = File('test/$nome').readAsBytesSync();
    return Uint8List.fromList(all.sublist(44));
  }

  List<Uint8List> chunks(Uint8List pcm, {int size = 2048}) {
    final out = <Uint8List>[];
    for (var i = 0; i < pcm.length; i += size) {
      out.add(Uint8List.sublistView(pcm, i, (i + size).clamp(0, pcm.length)));
    }
    return out;
  }

  Uint8List silencio({int ms = 2000}) => Uint8List(16000 * 2 * ms ~/ 1000);

  /// Corre uma frase e devolve quantas vezes a VAD a deu por acabada.
  /// Uma frase inteira tem de fechar UMA vez só, no fim.
  ({int fechos, int falaMs}) corre(String ficheiro) {
    final vad = Vad()..reset();
    var fechos = 0;
    var falaMs = 0;
    for (final c in chunks(wav(ficheiro))) {
      final r = vad.feed(c);
      if (r.isDone) {
        fechos++;
        falaMs = r.spokeMs;
        vad.newTurn();
      }
    }
    for (final c in chunks(silencio())) {
      final r = vad.feed(c);
      if (r.isDone) {
        fechos++;
        falaMs = r.spokeMs;
        // Como na app: depois de fechar, a frase seguinte comeca do zero.
        // Sem isto, cada pedaco de silencio a seguir contava como outro fecho.
        vad.newTurn();
      }
    }
    return (fechos: fechos, falaMs: falaMs);
  }

  test('uma frase com pausas a meio NAO e cortada em pedacos', () {
    // "Olá ORYKSA... quero marcar... uma reunião com a Ana... na sexta-feira"
    // As reticencias sao pausas a serio. Isto e o caso que parte tudo.
    final r = corre('pausas.wav');
    expect(r.fechos, 1, reason: 'a frase foi partida em ${r.fechos} pedacos');
    expect(r.falaMs, greaterThan(2000), reason: 'so apanhou ${r.falaMs} ms de fala');
  });

  test('uma frase curta fecha uma vez e tem fala que chegue', () {
    final r = corre('curta.wav');
    expect(r.fechos, 1);
    expect(r.falaMs, greaterThanOrEqualTo(Vad.minSpeechMs));
  });

  test('o silencio de fecho e o que esta escrito na constante', () {
    // Para ninguem o mudar sem passar por estes testes.
    expect(Vad.quietToCloseMs, inInclusiveRange(600, 900));
  });
}
