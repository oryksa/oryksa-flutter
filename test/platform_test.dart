import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/oryksa.dart';
import 'package:oryksa/src/http.dart' show oryksaSdkVersion;
import 'package:oryksa/src/platform.dart' show oryksaPlatform;

/// SDK-01: the owner's new-lead e-mail has to say whether the lead came from the
/// iPhone app or the Android app. The server reads `platform` from the body of
/// EVERY POST /v1/client/chat. Before this, the SDK only sent it when the message
/// carried voice numbers, so a typed lead arrived with no device at all.
void main() {
  Future<Map<String, dynamic>> enviar(Future<void> Function(OryksaClient) acao) async {
    late Map<String, dynamic> corpo;
    final c = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async {
        corpo = jsonDecode(req.body) as Map<String, dynamic>;
        corpo['_header_sdk'] = req.headers['X-ORYKSA-SDK'];
        return http.Response(jsonEncode({'status': 'replied', 'reply': 'ok'}), 200);
      }),
    );
    await acao(c);
    return corpo;
  }

  test('a mensagem escrita, sem voz nenhuma, leva o aparelho', () async {
    final corpo = await enviar((c) => c.send('Quanto custa?'));
    expect(corpo.containsKey('platform'), isTrue,
        reason: 'sem isto o aviso de lead do dono nao sabe dizer iPhone ou Android');
    expect(corpo['platform'], oryksaPlatform);
  });

  test('a mensagem de voz continua a levar o aparelho e os numeros', () async {
    final corpo = await enviar((c) => c.send('Quanto custa?', voice: true, voiceStats: {'peak': .05}));
    expect(corpo['platform'], oryksaPlatform);
    expect(corpo['voice_stats'], {'peak': .05});
  });

  test('o aparelho e o que o servidor sabe ler', () {
    expect(['ios', 'android', 'flutter'], contains(oryksaPlatform));
    // Nos testes corremos na maquina, nao num telemovel: aqui tem de ser 'flutter'.
    final esperado = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'flutter');
    expect(oryksaPlatform, esperado);
  });

  test('o cabecalho X-ORYKSA-SDK vai em cada pedido e diz a versao do pubspec', () async {
    final corpo = await enviar((c) => c.send('ola'));
    expect(corpo['_header_sdk'], 'flutter/$oryksaSdkVersion');

    // A versao do cabecalho tem de bater com o pubspec. Ficou em 1.2.1 enquanto o
    // pub.dev servia a 1.2.2, e todos os registos do servidor mentiam a versao.
    final linha = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(oryksaSdkVersion, linha.split(':')[1].trim());
  });
}
