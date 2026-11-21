import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/oryksa.dart';

// The reply the TugaFreela app showed as plain text on 21/11/2026 (owner: "os links ainda não estão clicáveis").
const reply = 'Sim, encontrei alguns webdesigners para criar sua landing page. Você pode conferir este serviço de '
    'landing page profissional focada em conversões:\n'
    'https://tugafreela.pt/wharakawa/criar-uma-landing-page-profissional-focada-em-conversoes\n'
    'Se quiser ver mais opções, aqui está a lista: https://tugafreela.pt/servico/explorar/28.';

OryksaClient fakeClient(List<String> asked) => OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/client/link-preview')) {
          final u = req.url.queryParameters['url']!;
          asked.add(u);
          return http.Response(
              jsonEncode({
                'object': 'link_preview',
                'url': u,
                'title': 'Eu vou criar uma landing page profissional focada em conversões',
                'image': '',
                'site': 'tugafreela.pt',
                'price': '',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('{}', 404);
      }),
    );

void main() {
  test('the links of a reply, in order, without the final dot', () {
    expect(oryksaLinksIn(reply), [
      'https://tugafreela.pt/wharakawa/criar-uma-landing-page-profissional-focada-em-conversoes',
      'https://tugafreela.pt/servico/explorar/28',
    ]);
  });

  test('the voice screen text has no addresses and no dangling colon', () {
    final t = oryksaWithoutLinks(reply);
    expect(t.contains('http'), isFalse);
    expect(t.contains('conversões:'), isFalse);
    expect(t, contains('focada em conversões'));
  });

  testWidgets('a link in the text is tappable and goes to the app first', (tester) async {
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OryksaRichText(reply, style: const TextStyle(), linkColor: Colors.green, onLink: (u) {
          opened = u;
          return true;
        }),
      ),
    ));
    final rich = tester.widget<SelectableText>(find.byType(SelectableText));
    final spans = <TextSpan>[];
    rich.textSpan!.visitChildren((s) {
      if (s is TextSpan && s.recognizer != null) spans.add(s);
      return true;
    });
    expect(spans.map((s) => s.text), [
      'https://tugafreela.pt/wharakawa/criar-uma-landing-page-profissional-focada-em-conversoes',
      'https://tugafreela.pt/servico/explorar/28',
    ]);
    (spans.first.recognizer! as TapGestureRecognizer).onTap!();
    expect(opened.toString(), 'https://tugafreela.pt/wharakawa/criar-uma-landing-page-profissional-focada-em-conversoes');
  });

  testWidgets('the card shows the title of the page and an Open button', (tester) async {
    final asked = <String>[];
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OryksaLinkCard(
          url: 'https://tugafreela.pt/wharakawa/criar-uma-landing-page-profissional-focada-em-conversoes',
          client: fakeClient(asked),
          openLabel: 'Abrir',
          onLink: (u) {
            opened = u;
            return true;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(asked.length, 1);
    expect(find.text('Eu vou criar uma landing page profissional focada em conversões'), findsOneWidget);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(opened?.host, 'tugafreela.pt');
  });
}
