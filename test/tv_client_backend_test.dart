import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/tv.dart';

// The real backend against the contract of sdk-tv/DESENHO.md section 9, with the HTTP
// simulated. This proves the requests the SDK sends and how it reads the answers; it does
// NOT prove the ORYKSA server.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('platform (S5)', () {
    test('a TV value goes in the chat and in client.ai; without it nothing changes', () async {
      final bodies = <String, Map<String, dynamic>>{};
      http.Client mock() => MockClient((req) async {
            bodies[req.url.path] = jsonDecode(req.body) as Map<String, dynamic>;
            if (req.url.path.endsWith('/client/ai')) return _json({'text': 'ok'});
            return _json({'status': 'replied', 'reply': 'ok'});
          });
      final tvClient = OryksaClient(token: 'oryk_cs_t', httpClient: mock(), platform: OryksaTvPlatform.fireTv.wire);
      expect(tvClient.platform, 'fire_tv');
      await tvClient.send('olá');
      expect(bodies['/v1/client/chat']!['platform'], 'fire_tv');
      await tvClient.ai(input: 'x');
      expect(bodies['/v1/client/ai']!['platform'], 'fire_tv');

      final phone = OryksaClient(token: 'oryk_cs_t', httpClient: mock());
      await phone.send('olá');
      expect(phone.platform, isNot('fire_tv'));
      expect(bodies['/v1/client/chat']!['platform'], phone.platform);
    });

    test('the public session sends platform and app_id only when given (S4)', () async {
      final seen = <Map<String, dynamic>>[];
      http.Client mock() => MockClient((req) async {
            if (req.url.path.endsWith('/public/sessions')) {
              seen.add(jsonDecode(req.body) as Map<String, dynamic>);
              return _json({'client_token': 'oryk_cs_new'}, 201);
            }
            return _json({'status': 'replied', 'reply': 'ok'});
          });
      final tv = OryksaClient.public(
          chatToken: 'oryk_pub_x', conversationId: 'c1', httpClient: mock(), platform: 'fire_tv', appId: 'tv.blinddating.app');
      await tv.send('olá');
      expect(seen.last['platform'], 'fire_tv');
      expect(seen.last['app_id'], 'tv.blinddating.app');
      expect(tv.platform, 'fire_tv');

      final phone = OryksaClient.public(chatToken: 'oryk_pub_x', conversationId: 'c1', httpClient: mock());
      await phone.send('olá');
      expect(seen.last.containsKey('platform'), isFalse);
      expect(seen.last.containsKey('app_id'), isFalse);
    });
  });

  group('presenter voice (S1)', () {
    test('sends text, locale, purpose presenter and platform; reads the new headers', () async {
      late http.Request seen;
      final c = OryksaClient(
        token: 'oryk_cs_t',
        platform: 'fire_tv',
        httpClient: MockClient((req) async {
          seen = req;
          return http.Response.bytes([1, 2, 3], 200, headers: {
            'content-type': 'audio/mpeg',
            'X-ORYKSA-Locale': 'es-419',
            'X-ORYKSA-Voice-Rev': 'a1b2c3d4e5f6',
            'X-ORYKSA-Interactions-Spent': '1',
          });
        }),
      );
      final sp = await OryksaTvClientBackend(c).speak('Hola', locale: 'es_MX');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/v1/client/tts');
      expect(jsonDecode(seen.body), {'text': 'Hola', 'locale': 'es-MX', 'purpose': 'presenter', 'platform': 'fire_tv'});
      expect(sp, isNotNull);
      expect(sp!.bytes, Uint8List.fromList([1, 2, 3]));
      expect(sp.locale, 'es-419');
      expect(sp.voiceRev, 'a1b2c3d4e5f6');
      expect(sp.interactionsSpent, 1);
    });

    test('voice_unavailable gives null (subtitles only); other errors throw', () async {
      var answer = _json({'error': {'code': 'voice_unavailable', 'message': 'no voice'}}, 503);
      final c = OryksaClient(token: 'oryk_cs_t', httpClient: MockClient((_) async => answer));
      final b = OryksaTvClientBackend(c);
      expect(await b.speak('Olá', locale: 'pt-PT'), isNull);
      answer = _json({'error': {'code': 'text_too_long', 'message': 'too long'}}, 400);
      await expectLater(b.speak('Olá', locale: 'pt-PT'),
          throwsA(isA<OryksaException>().having((e) => e.code, 'code', 'text_too_long')));
    });

    test('an expired token is renewed once for the voice', () async {
      var calls = 0;
      var tokens = 0;
      final c = OryksaClient(
        getToken: () async => 'oryk_cs_${++tokens}',
        httpClient: MockClient((req) async {
          calls++;
          if (req.headers['Authorization'] == 'Bearer oryk_cs_1') {
            return _json({'error': {'code': 'session_expired', 'message': 'expired'}}, 401);
          }
          return http.Response.bytes([9], 200, headers: {'content-type': 'audio/mpeg'});
        }),
      );
      final sp = await OryksaTvClientBackend(c).speak('Olá', locale: 'pt-PT');
      expect(sp!.bytes, [9]);
      expect(calls, 2);
      expect(tokens, 2);
    });
  });

  test('configuration: GET /client/agent?locale= (S2)', () async {
    late http.Request seen;
    final c = OryksaClient(
      token: 'oryk_cs_t',
      httpClient: MockClient((req) async {
        seen = req;
        return _json({
          'name': 'ORYKSA',
          'tv': {'locale': 'pt-BR', 'voice_rev': 'v1', 'texts': {'close': 'Fechar'}},
        });
      }),
    );
    final cfg = await OryksaTvClientBackend(c).config('pt_BR');
    expect(seen.method, 'GET');
    expect(seen.url.path, '/v1/client/agent');
    expect(seen.url.queryParameters['locale'], 'pt-BR');
    expect(cfg.locale, 'pt-BR');
    expect(cfg.voiceRev, 'v1');
    expect(cfg.texts.get('close'), 'Fechar');
  });

  test('chat from the panel sends the old language code and waits for the reply', () async {
    late Map<String, dynamic> body;
    final c = OryksaClient(
      token: 'oryk_cs_t',
      httpClient: MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'status': 'replied', 'reply': 'Olá!', 'speech': 'Olá!'});
      }),
    );
    final r = await OryksaTvClientBackend(c).chat('oi', locale: 'pt-BR', voice: true);
    expect(body['lang'], 'br');
    expect(body['voice'], isTrue);
    expect(r.reply, 'Olá!');
  });

  group('phone pairing (S3)', () {
    test('create, wait for events (long-poll) and close', () async {
      final seen = <http.Request>[];
      final c = OryksaClient(
        token: 'oryk_cs_t',
        platform: 'fire_tv',
        timeout: const Duration(seconds: 20),
        httpClient: MockClient((req) async {
          seen.add(req);
          if (req.method == 'POST') {
            return _json({
              'pair_id': 'tvp_9f2c41d0',
              'code': 'K7Q2MZ',
              'url': 'https://oryksa.com/tv?c=K7Q2MZ',
              'short_url': 'oryksa.com/tv',
              'qr_png_url': 'https://api.oryksa.com/v1/public/tv/qr/K7Q2MZ.png',
              'expires_in': 300,
            }, 201);
          }
          if (req.method == 'GET') {
            return _json({
              'state': 'paired',
              'next': 3,
              'events': [
                {'seq': 3, 'type': 'text', 'text': 'Olá', 'lang': 'pt-PT', 'final': true}
              ],
            });
          }
          return http.Response('', 204);
        }),
      );
      final b = OryksaTvClientBackend(c);
      final p = await b.pair('pt_PT');
      expect(seen[0].url.path, '/v1/client/tv/pair');
      expect(jsonDecode(seen[0].body), {'locale': 'pt-PT', 'platform': 'fire_tv'});
      expect(p.pairId, 'tvp_9f2c41d0');

      final page = await b.phoneEvents(p.pairId, after: 2);
      expect(seen[1].url.path, '/v1/client/tv/pair/tvp_9f2c41d0/events');
      expect(seen[1].url.queryParameters['after'], '2');
      expect(seen[1].url.queryParameters['wait'], '15', reason: 'kept 5 s under the client time limit of 20 s');
      expect(page.events.single.text, 'Olá');
      expect(page.next, 3);

      await b.unpair(p.pairId);
      expect(seen[2].method, 'DELETE');
      expect(seen[2].url.path, '/v1/client/tv/pair/tvp_9f2c41d0');
    });

    test('wait is never over 30 s (the server maximum), whatever the client time limit', () async {
      late http.Request seen;
      final c = OryksaClient(
        token: 'oryk_cs_t',
        timeout: const Duration(seconds: 120),
        httpClient: MockClient((req) async {
          seen = req;
          return _json({'state': 'waiting', 'next': 0, 'events': []});
        }),
      );
      await OryksaTvClientBackend(c).phoneEvents('tvp_x', wait: const Duration(seconds: 90));
      expect(seen.url.queryParameters['wait'], '30');
    });

    test('the simulated server answers 410 pair_expired after the end, as the real one', () async {
      final fake = OryksaTvFakeBackend();
      final p = await fake.pair('pt-PT');
      fake.expire();
      final page = await fake.phoneEvents(p.pairId);
      expect(page.state, 'expired');
      await expectLater(fake.phoneEvents(p.pairId, after: page.next),
          throwsA(isA<OryksaException>().having((e) => e.code, 'code', 'pair_expired')));
    });
  });
}
