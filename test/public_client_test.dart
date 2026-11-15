import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/oryksa.dart';

void main() {
  test('public client opens a session with the chat token, then chats with a photo', () async {
    final calls = <http.Request>[];
    final mock = MockClient((req) async {
      calls.add(req);
      if (req.url.path.endsWith('/public/sessions')) {
        final b = jsonDecode(req.body) as Map;
        expect(b['widget_token'], 'abcdef0123456789abcdef0123456789');
        expect(b['conversation_id'], 'device-1');
        expect(req.headers['authorization'], isNull);
        return http.Response(jsonEncode({'object': 'client_session', 'client_token': 'oryk_cs_test', 'conversation_id': 'pub_device-1'}), 201);
      }
      expect(req.headers['authorization'], 'Bearer oryk_cs_test');
      final b = jsonDecode(req.body) as Map;
      expect(b['image_base64'], base64Encode([1, 2, 3]));
      expect(b['image_mime'], 'image/png');
      return http.Response(jsonEncode({'object': 'chat_reply', 'status': 'replied', 'reply': 'ok', 'conversation_id': 'pub_device-1'}), 200);
    });
    final c = OryksaClient.public(chatToken: 'abcdef0123456789abcdef0123456789', conversationId: 'device-1', httpClient: mock);
    final r = await c.send('Este serve?', image: OryksaImage(Uint8List.fromList([1, 2, 3]), mime: 'image/png'));
    expect(r.reply, 'ok');
    expect(calls.length, 2);
  });

  test('public client reports a refused chat token', () async {
    final mock = MockClient((req) async =>
        http.Response(jsonEncode({'error': {'code': 'not_found', 'message': 'Unknown widget_token.'}}), 404));
    final c = OryksaClient.public(chatToken: 'abcdef0123456789abcdef0123456789', httpClient: mock);
    expect(() => c.send('hi'), throwsA(isA<OryksaException>().having((e) => e.code, 'code', 'not_found')));
  });
}
