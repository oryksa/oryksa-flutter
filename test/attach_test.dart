import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/oryksa.dart';

// Owner 2026-11-21: "o SDK tem que ter a opção de anexar a imagem, anexar documento, ligar a câmera".
void main() {
  test('a document goes to the server as file_base64 with its name and type', () async {
    Map<String, dynamic>? sent;
    final c = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'object': 'chat_reply', 'status': 'replied', 'reply': 'ok'}), 200);
      }),
    );
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 test'));
    await c.send('O que diz?', file: OryksaFile(bytes, name: 'orcamento.pdf', mime: 'application/pdf'));
    expect(sent!['file_name'], 'orcamento.pdf');
    expect(sent!['file_mime'], 'application/pdf');
    expect(base64Decode(sent!['file_base64'] as String), bytes);
    expect(sent!.containsKey('image_base64'), isFalse);
  });

  testWidgets('the chat shows the attach button with photo library, camera and document', (tester) async {
    final c = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/client/agent')) {
          return http.Response(jsonEncode({'object': 'agent', 'name': 'Manuel', 'voice_replies': false}), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response(jsonEncode({'object': 'conversation', 'messages': []}), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OryksaChat(client: c, lang: 'pt'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Anexar'));
    await tester.pumpAndSettle();
    expect(find.text('Foto da galeria'), findsOneWidget);
    expect(find.text('Câmara'), findsOneWidget);
    expect(find.text('Documento'), findsOneWidget);
  });

  testWidgets('attachments: false hides the button', (tester) async {
    final c = OryksaClient(token: 'oryk_cs_test', httpClient: MockClient((req) async => http.Response('{}', 404)));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OryksaChat(client: c, lang: 'pt', attachments: false))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Anexar'), findsNothing);
  });
}
