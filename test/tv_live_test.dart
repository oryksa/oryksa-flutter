// LIVE test against the real ORYKSA server. It USES ORYKSA INTERACTIONS of the account of the token (3 lines, charged
// by the ORYKSA interaction cost table: a spoken line at the voice price, a subtitles-only line at the text price), so it is
// opt-in: without ORYKSA_LIVE=1 it is skipped and `flutter test` (and CI) never calls the real server.
// Run it only with the token of a TEST account, given by the environment, never written in the repository:
//   ORYKSA_LIVE=1 ORYKSA_TV_TOKEN=<public chat token> flutter test test/tv_live_test.dart
//   ORYKSA_LIVE=1 ORYKSA_TV_TOKEN_FILE=<file with the public chat token> flutter test test/tv_live_test.dart
// Optional ORYKSA_PROOF_OUT=<log file>. The token is never printed; the log has paths, statuses and headers only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oryksa/tv.dart';

final bool _live = Platform.environment['ORYKSA_LIVE'] == '1';

/// The interactions the server charged for a logged line (`spent=N`), 0 when it sent none.
int _spentOf(String line) => int.tryParse(RegExp(r' spent=(\d+)').firstMatch(line)?.group(1) ?? '') ?? 0;

/// The token of the TEST account from the environment: ORYKSA_TV_TOKEN, or the file named by ORYKSA_TV_TOKEN_FILE.
String? _liveToken() {
  final v = Platform.environment['ORYKSA_TV_TOKEN']?.trim();
  if (v != null && v.isNotEmpty) return v;
  final f = Platform.environment['ORYKSA_TV_TOKEN_FILE'];
  if (f == null || f.isEmpty || !File(f).existsSync()) return null;
  final t = File(f).readAsStringSync().trim();
  return t.isEmpty ? null : t;
}

/// Logs each request: path, status and the ORYKSA headers, and for the presenter the fields sent. Never a body of
/// the session (it holds the token) and never the Authorization header.
class _Log extends http.BaseClient {
  _Log(this.out);
  final List<String> out;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    final r = await _inner.send(req);
    final bytes = await r.stream.toBytes();
    String h(String k) => r.headers[k] ?? '-';
    var sent = '';
    if (req is http.Request && req.url.path.endsWith('/client/tts')) {
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      sent = ' | sent voice=${b['voice'] ?? '-'} cached=${b['cached'] ?? '-'} voice_rev=${b['voice_rev'] ?? '-'} '
          'locale=${b['locale'] ?? '-'} text="${b['text']}"';
    }
    out.add('${DateTime.now().toUtc().toIso8601String()} ${req.method} ${req.url.path} status=${r.statusCode} '
        'spent=${h('x-oryksa-interactions-spent')} voice_status=${h('x-oryksa-voice-status')} '
        'voice_rev=${h('x-oryksa-voice-rev')} locale=${h('x-oryksa-locale')} bytes=${bytes.length}$sent');
    return http.StreamedResponse(Stream.value(bytes), r.statusCode,
        headers: r.headers, request: r.request, reasonPhrase: r.reasonPhrase, contentLength: bytes.length);
  }
}

class _Player implements OryksaTvAudioPlayer {
  final List<String> loaded = [];
  int plays = 0;

  @override
  Future<Duration?> load({String? file, Uint8List? bytes}) async {
    loaded.add(file ?? 'memory(${bytes?.length})');
    return const Duration(milliseconds: 50);
  }

  @override
  Future<void> play() async {
    plays++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('LIVE: a new line 200 + Spent >= 1; the same line again 204 cached + Spent >= 1 and the kept voice plays; '
      'voice: false 204 captions + Spent >= 1 and the subtitles show', () async {
    final token = _liveToken();
    if (token == null) fail('ORYKSA_LIVE=1 needs ORYKSA_TV_TOKEN or ORYKSA_TV_TOKEN_FILE (a TEST account).');
    final out = Platform.environment['ORYKSA_PROOF_OUT'];
    final log = <String>[];
    final client = OryksaClient.public(
      chatToken: token,
      conversationId: 'tvlive${DateTime.now().microsecondsSinceEpoch}',
      platform: OryksaTvPlatform.fireTv.wire,
      appId: 'com.oryksa.oryksa_tv_demo',
      httpClient: _Log(log),
    );
    final player = _Player();
    final tv = OryksaTv(client: client, locale: 'pt-BR', audioPlayer: () => player);
    tv.presenter.readingTime = (_) => const Duration(milliseconds: 50);
    final errors = <String>[];
    tv.presenter.onError = (e) => errors.add(e.toString());
    final shown = <String>[];
    tv.presenter.addListener(() {
      final l = tv.presenter.line;
      if (l.isNotEmpty && (shown.isEmpty || shown.last != l)) shown.add(l);
    });

    final stamp = DateTime.now().toUtc().toIso8601String().substring(11, 19);
    final line = 'Prova ao vivo da cobrança do SDK de TV, às $stamp.';
    final captions = 'Só legendas, sem som, às $stamp.';
    await tv.presenter.say(line); // 1: new
    await tv.presenter.say(line); // 2: the device has it
    await tv.presenter.say(captions, voice: false); // 3: subtitles only
    tv.dispose();

    final tts = log.where((l) => l.contains('/client/tts')).toList();
    final summary = [
      'Flutter SDK (ramo tv) contra o servidor real, conta de TESTE, ${DateTime.now().toUtc().toIso8601String()}',
      ...log,
      'player.loaded=${player.loaded}',
      'player.plays=${player.plays}',
      'shown=$shown',
      'errors=$errors',
      'spent (by the cost table, per line)=${tts.map(_spentOf).toList()}',
    ];
    if (out != null && out.isNotEmpty) File(out).writeAsStringSync('${summary.join('\n')}\n');

    expect(tts.length, 3);
    expect(tts[0], allOf(contains('status=200'), contains('sent voice=- cached=-')));
    expect(tts[1], allOf(contains('status=204'), contains('voice_status=cached'), contains('cached=true')));
    expect(tts[2], allOf(contains('status=204'), contains('voice_status=captions'), contains('voice=false')));
    // Every line is charged; the number is the cost table's, never fixed here.
    for (final l in tts) {
      expect(_spentOf(l), greaterThanOrEqualTo(1), reason: l);
    }
    expect(player.plays, 2);
    expect(player.loaded[1], player.loaded[0], reason: 'the kept voice plays the second time');
    expect(shown, contains(captions));
    expect(errors, isEmpty);
  },
      skip: _live ? false : 'live test: uses interactions; set ORYKSA_LIVE=1 and the token of a TEST account',
      timeout: const Timeout(Duration(minutes: 2)));
}
