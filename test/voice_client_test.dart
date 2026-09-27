import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/oryksa.dart';

void main() {
  test('voice message: sends voice, whisper, app context and stats; reads speech', () async {
    late Map<String, dynamic> sent;
    final c = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async {
        expect(req.url.path, '/v1/client/chat');
        expect(req.headers['Authorization'], 'Bearer oryk_cs_test');
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({'status': 'replied', 'reply': '**Yes!** It costs 59.90. Anything else?', 'speech': 'Yes! It costs 59.90.', 'whisper': true}),
            200);
      }),
    );
    final r = await c.sendAndWaitReply('How much?',
        voice: true,
        whisper: true,
        voiceStats: {'peak': .05, 'pitch': .3},
        appContext: const OryksaAppContext(screen: 'product', title: 'Lavender candle', items: ['Lavender candle']));
    expect(sent['voice'], true);
    expect(sent['whisper'], true);
    expect(sent['platform'], 'flutter');
    expect(sent['voice_stats']['peak'], .05);
    expect(sent['app_context'], {'screen': 'product', 'title': 'Lavender candle', 'items': ['Lavender candle']});
    expect(r.speech, 'Yes! It costs 59.90.');
    expect(r.whisper, true);
    expect(r.reply, startsWith('**Yes!**'));
  });

  test('tts returns the mp3 bytes, and null (silence + text) when the voice fails', () async {
    final ok = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async {
        expect(req.url.path, '/v1/client/tts');
        expect(jsonDecode(req.body), {'text': 'Hello', 'whisper': true});
        return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'audio/mpeg'});
      }),
    );
    expect(await ok.tts('Hello', whisper: true), Uint8List.fromList([1, 2, 3]));

    final refused = OryksaClient(
      token: 'oryk_cs_test',
      httpClient: MockClient((req) async => http.Response(jsonEncode({'error': {'code': 'not_a_reply', 'message': 'x'}}), 403)),
    );
    expect(await refused.tts('olá mundo'), isNull);
  });

  test('transcribe: text, empty when nothing was said, null on failure', () async {
    OryksaClient withBody(int status, Object body) => OryksaClient(
          token: 'oryk_cs_test',
          httpClient: MockClient((req) async {
            expect(req.url.path, '/v1/client/transcribe');
            expect(req.headers['content-type'], startsWith('multipart/form-data'));
            return http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});
          }),
        );
    final wav = OryksaVoiceController.wavForTest(Uint8List(3200));
    expect(await withBody(200, {'text': 'Olá'}).transcribe(wav), 'Olá');
    expect(await withBody(200, {'text': '', 'reason': 'no_speech'}).transcribe(wav), '');
    expect(await withBody(500, {'error': {'code': 'x', 'message': 'y'}}).transcribe(wav), isNull);
  });

  test('the recording is a 16 kHz mono PCM16 WAV', () {
    final wav = OryksaVoiceController.wavForTest(Uint8List(32000));
    final d = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(d.getUint16(22, Endian.little), 1);
    expect(d.getUint32(24, Endian.little), 16000);
    expect(d.getUint16(34, Endian.little), 16);
    expect(d.getUint32(40, Endian.little), 32000);
    expect(wav.length, 44 + 32000);
  });

  test('agent: photo is the AI photo, voice and language from ORYKSA', () {
    final a = OryksaAgent.fromJson({'name': 'Sofia', 'avatar': 'https://x/ai.jpg', 'voice': 'v123', 'language': 'pt', 'voice_replies': true});
    expect(a.name, 'Sofia');
    expect(a.photo, 'https://x/ai.jpg');
    expect(a.voice, 'v123');
    expect(a.language, 'pt');
    expect(a.voiceReplies, true);
  });
}
