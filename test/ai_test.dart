import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/oryksa.dart';

// Owner 2026-11-21: the SDK lets the developer have the AI do what THEY want in the app,
// counted as ORYKSA interactions.
void main() {
  test('ai() sends instructions, photos and the schema to /client/ai and reads the JSON answer', () async {
    late http.Request seen;
    final c = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'object': 'ai_result',
              'text': '{"size":"205/55 R16 91V"}',
              'json': {'size': '205/55 R16 91V'},
              'oryksa': {'interactions_spent': 1, 'interactions_remaining': 99}
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final img = Uint8List.fromList([1, 2, 3]);
    final r = await c.ai(
      instructions: 'Read the tyre size. Never invent.',
      images: [OryksaImage(img)],
      schema: {
        'type': 'object',
        'properties': {
          'size': {'type': ['string', 'null']}
        }
      },
    );
    expect(seen.url.path, endsWith('/client/ai'));
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['instructions'], 'Read the tyre size. Never invent.');
    expect((body['images'] as List).single['mime'], 'image/jpeg');
    expect(base64Decode((body['images'] as List).single['base64'] as String), img);
    expect(body['schema'], isA<Map>());
    expect(body.containsKey('message'), isFalse);
    expect(r.json?['size'], '205/55 R16 91V');
    expect(r.interactionsSpent, 1);
    expect(r.interactionsRemaining, 99);
  });

  test('ai() without a schema gives the text and no json', () async {
    final c = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async => http.Response(
          jsonEncode({'object': 'ai_result', 'text': 'Lisboa.', 'json': null, 'oryksa': {'interactions_spent': 1}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'})),
    );
    final r = await c.ai(input: 'Capital de Portugal?');
    expect(r.text, 'Lisboa.');
    expect(r.json, isNull);
  });

  test('ai() refuses an empty call and more than 4 photos', () async {
    final c = OryksaClient(token: 'oryk_cs_test', httpClient: MockClient((req) async => http.Response('{}', 200)));
    expect(() => c.ai(), throwsArgumentError);
    final p = OryksaImage(Uint8List.fromList([1]));
    expect(() => c.ai(input: 'x', images: [p, p, p, p, p]), throwsArgumentError);
  });

  test('an interaction limit comes back as an OryksaException 402', () async {
    final c = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async => http.Response(
          jsonEncode({'error': {'code': 'interaction_limit_reached', 'message': 'limit'}}), 402,
          headers: {'content-type': 'application/json'})),
    );
    await expectLater(c.ai(input: 'x'), throwsA(isA<OryksaException>().having((e) => e.status, 'status', 402)));
  });
}
