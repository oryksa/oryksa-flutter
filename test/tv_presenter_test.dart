import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/tv.dart';

// The presenter and the phone voice on the SIMULATED backend: this proves the SDK logic
// (cache, subtitles, events), not the ORYKSA server.
class FakePlayer implements OryksaTvAudioPlayer {
  FakePlayer({this.playFor = const Duration(milliseconds: 60)});

  final Duration playFor;
  final List<String> loaded = [];
  int plays = 0;
  int stops = 0;
  Completer<void>? _c;
  Timer? _t;

  @override
  Future<Duration?> load({String? file, Uint8List? bytes}) async {
    loaded.add(file ?? 'memory');
    return playFor;
  }

  @override
  Future<void> play() {
    plays++;
    final c = _c = Completer<void>();
    _t?.cancel();
    _t = Timer(playFor, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    _t?.cancel();
    final c = _c;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> dispose() async => _t?.cancel();
}

/// A simulated backend whose configuration revision can change, as the server's.
class _RevBackend extends OryksaTvFakeBackend {
  _RevBackend({super.voice, required this.rev, required this.onRead});
  final String Function() rev;
  final void Function() onRead;

  @override
  Future<OryksaTvConfig> config(String locale) async {
    onRead();
    return OryksaTvConfig(locale: 'pt-BR', voiceRev: rev(), presenterName: 'ORYKSA', presenterAvatar: OryksaTvConfig.defaultAvatar);
  }
}

/// A server that answers the line without counting it (no `X-ORYKSA-Interactions-Spent`), or
/// refuses it because no interactions are left.
class _NotCounting extends OryksaTvFakeBackend {
  _NotCounting({super.voice, this.refuse = false});
  final bool refuse;

  @override
  Future<OryksaTvSpeech?> speak(String text, {required String locale, bool whisper = false, bool voice = true, String? cachedRev}) async {
    final s = await super.speak(text, locale: locale, whisper: whisper, voice: voice, cachedRev: cachedRev);
    if (refuse) throw const OryksaException(402, 'interactions_exhausted', 'No interactions left.');
    return OryksaTvSpeech(s!.bytes, locale: s.locale, voiceRev: s.voiceRev);
  }
}

/// Today's server, which does not know `cached` yet: it makes the voice again (and counts it).
class _NoCachedHint extends OryksaTvFakeBackend {
  _NoCachedHint({super.voice});

  @override
  Future<OryksaTvSpeech?> speak(String text, {required String locale, bool whisper = false, bool voice = true, String? cachedRev}) =>
      super.speak(text, locale: locale, whisper: whisper, voice: voice);
}

Uint8List _mp3(String text, String locale) => Uint8List.fromList([0xFF, 0xFB, ...text.codeUnits.take(8)]);

/// A text no earlier run has cached on this machine.
String _fresh(String s) => '$s ${DateTime.now().microsecondsSinceEpoch}.';

void main() {
  group('presenter', () {
    test('speaks with the voice of the locale; the same line again is counted again (1 each time) and plays the kept voice', () async {
      final fake = OryksaTvFakeBackend(voice: _mp3);
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(fake, locale: 'pt-BR', audioPlayer: () => player);
      final events = <String>[];
      tv.presenter.onStart = () => events.add('start');
      tv.presenter.onEnd = () => events.add('end');
      final phases = <OryksaPresenterPhase>{};
      tv.presenter.addListener(() => phases.add(tv.presenter.phase));

      final line = _fresh('Olá! Sou a ORYKSA');
      await tv.presenter.say(line);
      expect(fake.speakCalls, 1);
      expect(player.plays, 1);
      expect(player.loaded.single, isNot('memory'), reason: 'plays from a file (Android 9 blocks the memory proxy)');
      expect(phases, containsAll([OryksaPresenterPhase.preparing, OryksaPresenterPhase.speaking, OryksaPresenterPhase.idle]));
      expect(events, ['start', 'end']);
      expect(tv.presenter.isBusy, isFalse);

      await tv.presenter.say(line);
      expect(fake.speakCalls, 2, reason: 'each time she says it, it counts (owner, 26/11/2026)');
      expect(fake.speakRequests.last.cachedRev, 'sim-1', reason: 'the server is told the device has it, so it need not make the voice again');
      expect(player.plays, 2);
      expect(player.loaded.last, player.loaded.first, reason: 'the kept voice plays');
      tv.dispose();
    });

    test("today's server does not know `cached` yet: it sends the voice again, which plays, and counts 1", () async {
      final fake = _NoCachedHint(voice: _mp3);
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(fake, locale: 'pt-BR', audioPlayer: () => player);
      final line = _fresh('Olá de novo');
      await tv.presenter.say(line);
      await tv.presenter.say(line);
      expect(fake.speakCalls, 2);
      expect(player.plays, 2);
      tv.dispose();
    });

    test('a server without voice_rev in the configuration: the line said again is counted again', () async {
      // Fire TV 26/11: with S2 not live yet, the same it-IT line was asked twice (2 interactions).
      final fake = OryksaTvFakeBackend(
        voice: _mp3,
        fixedConfig: const OryksaTvConfig(
          locale: 'it-IT',
          presenterName: 'ORYKSA',
          presenterAvatar: OryksaTvConfig.defaultAvatar,
          fromServer: false,
        ),
      );
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(fake, locale: 'it-IT', audioPlayer: () => player);
      final line = _fresh('Ciao! Sono ORYKSA');
      await tv.presenter.say(line);
      await tv.presenter.say(line);
      expect(fake.speakCalls, 2);
      expect(fake.speakRequests.last.cachedRev, 'sim-1', reason: 'the revision the voice came with');
      expect(player.plays, 2);
      tv.dispose();
    });

    test('a voice that does not match the configuration makes it read again; then the new revision is used', () async {
      // 26/11/2026 the pt-BR voice changed on the server (99cb5c17c2ff -> 9870f9eea051) while apps may be open.
      var reads = 0;
      var serverRev = 'old-rev';
      final fake = _RevBackend(voice: _mp3, rev: () => serverRev, onRead: () => reads++); // voices come as sim-1
      final tv = OryksaTv.withBackend(fake, locale: 'pt-BR', audioPlayer: FakePlayer.new);
      final line = _fresh('Uma frase');
      await tv.presenter.say(line);
      expect(reads, 1);
      serverRev = 'sim-1';
      await tv.presenter.say(line);
      expect(reads, 2, reason: 'the voice came as sim-1 but the configuration said old-rev');
      expect(fake.speakCalls, 2, reason: 'counted each time');
      expect(fake.speakRequests.last.cachedRev, 'sim-1', reason: 'then kept under the new revision');
      tv.dispose();
    });

    test('the configuration is kept 10 minutes', () async {
      var reads = 0;
      final tv = OryksaTv.withBackend(_RevBackend(rev: () => 'r', onRead: () => reads++), locale: 'pt-BR', audioPlayer: FakePlayer.new);
      await tv.config();
      await tv.config();
      expect(reads, 1);
      tv.configTtl = Duration.zero;
      await tv.config();
      expect(reads, 2);
      tv.dispose();
    });

    test('without voice she shows the subtitles one by one, at reading speed, never a robot voice', () async {
      final fake = OryksaTvFakeBackend(); // no voice
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(fake, locale: 'pt-PT', audioPlayer: () => player);
      tv.presenter.readingTime = (_) => const Duration(milliseconds: 30);
      final lines = <String>[];
      tv.presenter.addListener(() {
        final l = tv.presenter.line;
        if (l.isNotEmpty && (lines.isEmpty || lines.last != l)) lines.add(l);
      });
      await tv.presenter.say(_fresh('Bem-vindo. Vamos começar'));
      expect(fake.speakCalls, 1);
      expect(player.plays, 0);
      expect(lines.length, 2);
      expect(lines.first, 'Bem-vindo.');
      tv.dispose();
    });

    test('voice: false shows the subtitles only, at reading speed, with no sound, and counts 1', () async {
      final server = OryksaTvFakeBackend(voice: _mp3);
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(server, locale: 'pt-BR', audioPlayer: () => player);
      tv.presenter.readingTime = (_) => const Duration(milliseconds: 200);
      final events = <String>[];
      tv.presenter.onStart = () => events.add('start');
      tv.presenter.onEnd = () => events.add('end');
      final lines = <String>[];
      final phases = <OryksaPresenterPhase>{};
      tv.presenter.addListener(() {
        phases.add(tv.presenter.phase);
        final l = tv.presenter.line;
        if (l.isNotEmpty && (lines.isEmpty || lines.last != l)) lines.add(l);
      });

      final clock = Stopwatch()..start();
      await tv.presenter.say('Encontramos alguém para você. Boa sorte!', voice: false);
      clock.stop();
      expect(server.speakCalls, 1, reason: 'counted 1 by the server, like a spoken line (owner, 26/11/2026)');
      expect(server.speakRequests.single.voice, isFalse, reason: 'no voice asked for');
      expect(player.loaded, isEmpty);
      expect(player.plays, 0);
      expect(lines, ['Encontramos alguém para você.', 'Boa sorte!']);
      expect(clock.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 400)), reason: 'each line stays its reading time');
      expect(phases, containsAll([OryksaPresenterPhase.speaking, OryksaPresenterPhase.idle]));
      expect(events, ['start', 'end']);
      expect(tv.presenter.isBusy, isFalse);
      expect(tv.presenter.line, isEmpty);
      tv.dispose();
    });

    group('on the real client (HTTP simulated)', () {
      Future<({List<Map<String, dynamic>> tts, List<String> lines, List<Object> errors})> run(
          String text, bool voice, http.Response Function() answer) async {
        final tts = <Map<String, dynamic>>[];
        final client = OryksaClient(
          token: 'oryk_cs_t',
          platform: OryksaTvPlatform.fireTv.wire,
          httpClient: MockClient((req) async {
            if (!req.url.path.endsWith('/client/tts')) return http.Response('{"error":{"code":"down"}}', 500);
            tts.add(jsonDecode(req.body) as Map<String, dynamic>);
            return answer();
          }),
        );
        final tv = OryksaTv(client: client, locale: 'es-ES', audioPlayer: FakePlayer.new);
        tv.presenter.readingTime = (_) => const Duration(milliseconds: 10);
        final lines = <String>[];
        final errors = <Object>[];
        tv.presenter.onError = errors.add;
        tv.presenter.addListener(() {
          final l = tv.presenter.line;
          if (l.isNotEmpty && (lines.isEmpty || lines.last != l)) lines.add(l);
        });
        await tv.presenter.say(text, voice: voice);
        tv.dispose();
        return (tts: tts, lines: lines, errors: errors);
      }

      test('voice: false asks the server with "voice": false; counted (204 with Spent 1), the subtitles show', () async {
        final r = await run(_fresh('Hola. Hoy hablamos de viajes'), false,
            () => http.Response('', 204, headers: {'x-oryksa-interactions-spent': '1', 'x-oryksa-locale': 'es-ES'}));
        expect(r.tts.length, 1);
        expect(r.tts.single['voice'], false);
        expect(r.tts.single['purpose'], 'presenter');
        expect(r.lines.first, 'Hola.');
        expect(r.errors, isEmpty);
      });

      test('a line the server did not count (no Spent header) is not shown', () async {
        final r = await run(_fresh('Hola. Hoy hablamos de viajes'), false, () => http.Response('', 204));
        expect(r.tts.length, 1);
        expect(r.lines, isEmpty);
        expect(r.errors.single, isA<OryksaException>().having((e) => e.code, 'code', 'not_counted'));
      });

      test('no interactions left (402): nothing is shown, the next pieces are not asked', () async {
        final long = List.generate(30, (i) => 'Frase número $i de un texto largo para la presentadora.').join(' ');
        final r = await run(long, true,
            () => http.Response('{"error":{"code":"interactions_exhausted","message":"No interactions left."}}', 402));
        expect(r.tts.length, 1, reason: 'she stops at the first piece not counted');
        expect(r.lines, isEmpty);
        expect(r.errors.single, isA<OryksaException>().having((e) => e.code, 'code', 'interactions_exhausted'));
      });

      test('a network error: nothing is shown (before, the subtitles showed without being counted)', () async {
        final r = await run(_fresh('Hola'), true, () => throw http.ClientException('no network'));
        expect(r.lines, isEmpty);
        expect(r.errors, isNotEmpty);
      });
    });

    test('a spoken line the server did not count is not shown and plays no sound', () async {
      final fake = _NotCounting(voice: _mp3);
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(fake, locale: 'pt-BR', audioPlayer: () => player);
      final lines = <String>[];
      tv.presenter.addListener(() {
        if (tv.presenter.line.isNotEmpty) lines.add(tv.presenter.line);
      });
      await tv.presenter.say(_fresh('Olá'));
      expect(fake.speakCalls, 1);
      expect(player.plays, 0);
      expect(lines, isEmpty);
      tv.dispose();
    });

    test('a repeated line the server refuses (no interactions left) does not play the kept voice', () async {
      final ok = OryksaTvFakeBackend(voice: _mp3);
      final line = _fresh('Boa noite');
      final first = OryksaTv.withBackend(ok, locale: 'pt-BR', audioPlayer: FakePlayer.new);
      await first.presenter.say(line); // now kept on the device
      first.dispose();
      final refusing = _NotCounting(voice: _mp3, refuse: true);
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(refusing, locale: 'pt-BR', audioPlayer: () => player);
      tv.presenter.readingTime = (_) => const Duration(milliseconds: 10);
      final errors = <Object>[];
      tv.presenter.onError = errors.add;
      await tv.presenter.say(line);
      expect(refusing.speakCalls, 1);
      expect(player.plays, 0, reason: 'before, a kept line played with no request at all');
      expect(errors.single, isA<OryksaException>().having((e) => e.status, 'status', 402));
      tv.dispose();
    });

    test('OK and Back stop a text-only line: stop() ends it now and say() returns', () async {
      final tv = OryksaTv.withBackend(OryksaTvFakeBackend(), locale: 'pt-PT', audioPlayer: FakePlayer.new);
      tv.presenter.readingTime = (_) => const Duration(seconds: 30);
      final done = tv.presenter.say('Uma linha só para ler.', voice: false);
      while (tv.presenter.phase != OryksaPresenterPhase.speaking) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(tv.presenter.line, 'Uma linha só para ler.');
      await tv.presenter.stop();
      await done.timeout(const Duration(seconds: 2));
      expect(tv.presenter.isBusy, isFalse);
      expect(tv.presenter.line, isEmpty);
      tv.dispose();
    });

    test('a spoken line given during a text-only one replaces it', () async {
      final fake = OryksaTvFakeBackend(voice: _mp3);
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(fake, locale: 'pt-BR', audioPlayer: () => player);
      tv.presenter.readingTime = (_) => const Duration(seconds: 30);
      final first = tv.presenter.say('Linha para ler.', voice: false);
      while (tv.presenter.phase != OryksaPresenterPhase.speaking) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await tv.presenter.say(_fresh('Agora com voz'));
      await first.timeout(const Duration(seconds: 2));
      expect(fake.speakCalls, 2, reason: 'the text-only line counted 1, the spoken one 1');
      expect(player.plays, 1);
      expect(tv.presenter.isBusy, isFalse);
      tv.dispose();
    });

    test('sayGenerated with voice: false counts the AI answer and the line, with no sound', () async {
      final fake = OryksaTvFakeBackend(voice: _mp3);
      final player = FakePlayer();
      final tv = OryksaTv.withBackend(fake, locale: 'pt-BR', audioPlayer: () => player);
      tv.presenter.readingTime = (_) => const Duration(milliseconds: 10);
      final text = await tv.presenter.sayGenerated(instructions: 'Say goodbye.', input: _fresh('Ana'), voice: false);
      expect(text, isNotEmpty);
      expect(fake.aiCalls, 1);
      expect(fake.speakCalls, 1);
      expect(fake.speakRequests.single.voice, isFalse);
      expect(player.plays, 0);
      tv.dispose();
    });

    test('stop() ends her now and say() returns', () async {
      final fake = OryksaTvFakeBackend(voice: _mp3);
      final player = FakePlayer(playFor: const Duration(seconds: 30));
      final tv = OryksaTv.withBackend(fake, locale: 'pt-PT', audioPlayer: () => player);
      final done = tv.presenter.say(_fresh('Uma fala muito longa'));
      while (tv.presenter.phase != OryksaPresenterPhase.speaking) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await tv.presenter.stop();
      await done.timeout(const Duration(seconds: 2));
      expect(tv.presenter.isBusy, isFalse);
      expect(player.stops, greaterThan(0));
      tv.dispose();
    });

    test('a text longer than the server limit is sent in pieces', () async {
      final fake = OryksaTvFakeBackend(
        voice: _mp3,
        fixedConfig: const OryksaTvConfig(
          locale: 'pt-PT',
          voiceRev: 'sim-limit',
          presenterName: 'ORYKSA',
          presenterAvatar: OryksaTvConfig.defaultAvatar,
          rules: OryksaTvRules(presenterMaxChars: 60),
        ),
      );
      final tv = OryksaTv.withBackend(fake, locale: 'pt-PT', audioPlayer: FakePlayer.new);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      await tv.presenter.say(List.generate(4, (i) => 'Esta é a frase $i da apresentadora $stamp.').join(' '));
      expect(fake.speakCalls, greaterThan(1));
      tv.dispose();
    });

    test('sayGenerated asks client.ai in the locale, then speaks the answer', () async {
      final fake = OryksaTvFakeBackend(voice: _mp3);
      final tv = OryksaTv.withBackend(fake, locale: 'es-MX', audioPlayer: FakePlayer.new);
      final text = await tv.presenter.sayGenerated(instructions: 'Announce the next date.', input: _fresh('Ana and Rui'));
      expect(fake.aiCalls, 1);
      expect(text, startsWith('(simulated)'));
      expect(fake.speakCalls, 1);
      tv.dispose();
    });
  });

  group('phone voice', () {
    test('QR, the phone connects, what the person says arrives as text, Stop ends the pairing', () async {
      final fake = OryksaTvFakeBackend();
      final tv = OryksaTv.withBackend(fake, locale: 'pt-PT', audioPlayer: FakePlayer.new);
      final pv = tv.phoneVoice
        ..pollWait = const Duration(milliseconds: 50)
        ..retryPause = const Duration(milliseconds: 10);
      final heard = <String>[];
      final onText = <String>[];
      final sub = pv.texts.listen(heard.add);
      pv.onText = onText.add;

      await pv.start();
      expect(pv.state, OryksaPhoneVoiceState.waiting);
      expect(pv.pairing!.code, 'K7Q2MZ');

      Future<void> until(bool Function() ok) async {
        for (var i = 0; i < 200 && !ok(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(ok(), isTrue);
      }

      fake.phoneConnects();
      await until(() => pv.state == OryksaPhoneVoiceState.paired);
      fake.phoneSays('Como funciona o encontro?');
      await until(() => heard.isNotEmpty);
      expect(heard, ['Como funciona o encontro?']);
      expect(onText, ['Como funciona o encontro?']);
      expect(pv.lastText, 'Como funciona o encontro?');

      fake.phoneLeaves();
      await until(() => pv.state == OryksaPhoneVoiceState.phoneLeft);

      await pv.stop();
      expect(pv.state, OryksaPhoneVoiceState.idle);
      expect(fake.unpaired, [OryksaTvFakeBackend.pairIdOf(1)]);
      await sub.cancel();
      tv.dispose();
    });

    test('an expired code stops the waiting; restart gives a new code', () async {
      final fake = OryksaTvFakeBackend();
      final tv = OryksaTv.withBackend(fake, locale: 'pt-PT', audioPlayer: FakePlayer.new);
      final pv = tv.phoneVoice..pollWait = const Duration(milliseconds: 50);
      await pv.start();
      fake.expire();
      for (var i = 0; i < 200 && pv.state != OryksaPhoneVoiceState.expired; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(pv.state, OryksaPhoneVoiceState.expired);
      expect(pv.isActive, isFalse);
      await pv.restart();
      expect(pv.state, OryksaPhoneVoiceState.waiting);
      expect(pv.pairing!.code, 'H4PRWX');
      expect(fake.unpaired, [OryksaTvFakeBackend.pairIdOf(1)]);
      await pv.stop();
      tv.dispose();
    });
  });
}
