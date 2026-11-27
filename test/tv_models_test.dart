import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/tv.dart';

// TV SDK (26/11/2026): the contract approved by the MASTER, section 9 of sdk-tv/DESENHO.md.
void main() {
  group('locale', () {
    test('normalises to BCP-47 with a hyphen', () {
      expect(oryksaTvNormalizeLocale('pt_br'), 'pt-BR');
      expect(oryksaTvNormalizeLocale('ES-419'), 'es-419');
      expect(oryksaTvNormalizeLocale('zh_hant_tw'), 'zh-Hant-TW');
      expect(oryksaTvNormalizeLocale('  '), '');
      expect(oryksaTvLocaleTag(const Locale('pt', 'PT')), 'pt-PT');
      expect(oryksaTvLocaleTag(const Locale('fr')), 'fr');
    });

    test('the chat keeps its old language codes (br for Brazil)', () {
      expect(oryksaTvChatLang('pt-BR'), 'br');
      expect(oryksaTvChatLang('pt-PT'), 'pt');
      expect(oryksaTvChatLang('es-419'), 'es');
      expect(oryksaTvChatLang('en-GB'), 'en');
      expect(oryksaTvChatLang('de-DE'), 'de');
    });

    test('the simulated server picks the same locales as the approved table', () {
      expect(OryksaTvFakeBackend.resolveLocale('pt-BR'), 'pt-BR');
      expect(OryksaTvFakeBackend.resolveLocale('pt-AO'), 'pt-PT');
      expect(OryksaTvFakeBackend.resolveLocale('es-MX'), 'es-419');
      expect(OryksaTvFakeBackend.resolveLocale('es-ES'), 'es-ES');
      expect(OryksaTvFakeBackend.resolveLocale('fr-CA'), 'fr-FR');
      expect(OryksaTvFakeBackend.resolveLocale('en-GB'), 'en-GB');
      expect(OryksaTvFakeBackend.resolveLocale('it-IT'), 'en-US');
    });
  });

  group('configuration (GET /client/agent?locale=, block tv)', () {
    test('reads the whole tv block of the contract', () {
      final c = OryksaTvConfig.fromAgentJson({
        'name': 'ORYKSA',
        'avatar': 'https://x/a.png',
        'tv': {
          'locale': 'pt-BR',
          'voice_rev': 'v7f3a',
          'presenter': {'name': 'ORYKSA', 'avatar': 'https://x/p.png'},
          'texts': {'pair_step_code': 'Ou abra {url} e digite {code}', 'close': 'Fechar'},
          'suggestions': ['Como funciona?', ' ', 'O que você pode fazer?'],
          'actions': [
            {'id': 'phone_voice', 'kind': 'phone_voice', 'label': 'Falar pelo celular'},
            {'id': 'help', 'kind': 'message', 'label': 'Ajuda', 'message': 'Preciso de ajuda'},
            {'id': 'bad', 'kind': 'message', 'label': 'Sem mensagem'},
            {'id': 'new', 'kind': 'teleport', 'label': 'Novo'},
          ],
          'rules': {'phone_voice': true, 'tv_mic': 'off', 'speak_replies': false, 'presenter_max_chars': 300},
        },
      }, requestedLocale: 'pt-BR');
      expect(c.fromServer, isTrue);
      expect(c.locale, 'pt-BR');
      expect(c.voiceRev, 'v7f3a');
      expect(c.presenterAvatar, 'https://x/p.png');
      expect(c.suggestions, ['Como funciona?', 'O que você pode fazer?']);
      expect(c.actions.map((a) => a.id), ['phone_voice', 'help']);
      expect(c.actions.first.kind, OryksaTvActionKind.phoneVoice);
      expect(c.actions[1].message, 'Preciso de ajuda');
      expect(c.rules.tvMic, 'off');
      expect(c.rules.speakReplies, isFalse);
      expect(c.rules.presenterMaxChars, 300);
      expect(c.texts.get('pair_step_code', {'url': 'oryksa.com/tv', 'code': 'K7Q2MZ'}), 'Ou abra oryksa.com/tv e digite K7Q2MZ');
      expect(c.texts.get('close'), 'Fechar');
      expect(c.texts.get('retry'), 'Try again', reason: 'a missing key uses the English fallback');
    });

    test('an older server without tv block still works, with the English fallback', () {
      final c = OryksaTvConfig.fromAgentJson({'name': 'Ana', 'avatar': 'https://x/a.png'}, requestedLocale: 'fr_ca');
      expect(c.fromServer, isFalse);
      expect(c.locale, 'fr-CA');
      expect(c.voiceRev, isNull);
      expect(c.presenterName, 'Ana');
      expect(c.presenterAvatar, 'https://x/a.png');
      expect(c.rules.phoneVoice, isTrue);
      expect(c.rules.presenterMaxChars, 600);
      expect(c.texts.get('pair_title'), 'Talk on your phone');
    });
  });

  group('pairing (POST /client/tv/pair and the events)', () {
    test('reads the pairing', () {
      final p = OryksaPairing.fromJson({
        'pair_id': 'tvp_9f2c41d0',
        'code': 'K7Q2MZ',
        'url': 'https://oryksa.com/tv?c=K7Q2MZ',
        'short_url': 'oryksa.com/tv',
        'qr_png_url': 'https://api.oryksa.com/v1/public/tv/qr/K7Q2MZ.png',
        'expires_in': 300,
      });
      expect(p.code, 'K7Q2MZ');
      expect(p.shortUrl, 'oryksa.com/tv');
      expect(p.expiresIn, const Duration(minutes: 5));
      expect(p.expiresAt.difference(p.createdAt), const Duration(minutes: 5));
    });

    test('a pairing without id or code is refused', () {
      expect(() => OryksaPairing.fromJson({'code': 'X'}), throwsFormatException);
      expect(() => OryksaPairing.fromJson({'pair_id': 'x'}), throwsFormatException);
    });

    test('reads a page of events; next follows the highest seq; unknown types are kept as unknown', () {
      final page = OryksaPhoneEventsPage.fromJson({
        'state': 'paired',
        'next': 2,
        'events': [
          {'seq': 1, 'type': 'paired'},
          {'seq': 2, 'type': 'listening'},
          {'seq': 3, 'type': 'text', 'text': 'Como funciona o encontro?', 'lang': 'pt-BR', 'final': true},
          {'seq': 4, 'type': 'hologram'},
        ],
      }, after: 0);
      expect(page.state, 'paired');
      expect(page.next, 4);
      expect(page.events.map((e) => e.type), [
        OryksaPhoneEventType.paired,
        OryksaPhoneEventType.listening,
        OryksaPhoneEventType.text,
        OryksaPhoneEventType.unknown,
      ]);
      expect(page.events[2].text, 'Como funciona o encontro?');
      expect(page.events[2].lang, 'pt-BR');
    });

    test('the real S3 answer: object, phone and events_url are read or ignored', () {
      final page = OryksaPhoneEventsPage.fromJson(
          {'object': 'tv_pair_events', 'state': 'paired', 'phone': true, 'next': 1, 'events': [{'seq': 1, 'type': 'paired'}]},
          after: 0);
      expect(page.phoneConnected, isTrue);
      expect(OryksaPhoneEventsPage.fromJson({'state': 'waiting'}, after: 0).phoneConnected, isNull);
      final p = OryksaPairing.fromJson({
        'pair_id': 'tvp_0123456789ab',
        'code': 'K7Q2MZ',
        'url': 'https://oryksa.com/tv?c=K7Q2MZ',
        'short_url': 'oryksa.com/tv',
        'qr_png_url': 'https://api.oryksa.com/v1/public/tv/qr/K7Q2MZ.png',
        'expires_in': 300,
        'events_url': '/v1/client/tv/pair/tvp_0123456789ab/events',
      });
      expect(p.pairId, 'tvp_0123456789ab');
    });

    test('an empty long-poll answer keeps after', () {
      final page = OryksaPhoneEventsPage.fromJson({'state': 'waiting', 'events': []}, after: 7);
      expect(page.next, 7);
      expect(page.events, isEmpty);
    });
  });

  group('text for the voice and the subtitles', () {
    test('a long text is split under the limit at the end of sentences', () {
      final s = List.generate(12, (i) => 'Esta é a frase número $i da apresentadora.').join(' ');
      final parts = oryksaTvSplitForSpeech(s, 120);
      expect(parts.length, greaterThan(1));
      for (final p in parts) {
        expect(p.length, lessThanOrEqualTo(120));
        expect(p.endsWith('.'), isTrue);
      }
      expect(parts.join(' '), s);
    });

    test('a sentence longer than the limit is cut at a comma or a space', () {
      final s = 'Uma frase muito comprida, ${'com muitas palavras ' * 20}e um fim.';
      final parts = oryksaTvSplitForSpeech(s, 80);
      for (final p in parts) {
        expect(p.length, lessThanOrEqualTo(80));
      }
      expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' '), s.replaceAll(RegExp(r'\s+'), ' ').trim());
    });

    test('subtitles: one sentence per line', () {
      expect(oryksaTvSubtitleLines('Olá! Sou a ORYKSA. Vamos começar?'), ['Olá!', 'Sou a ORYKSA.', 'Vamos começar?']);
    });

    test('reading time: about 14 characters a second, never under 1.8 s', () {
      expect(oryksaTvReadingTime('Olá!'), const Duration(milliseconds: 1800));
      expect(oryksaTvReadingTime('a' * 70), const Duration(milliseconds: 5000));
    });
  });

  test('the TV platforms of the contract', () {
    expect(OryksaTvPlatform.values.map((p) => p.wire),
        ['android_tv', 'fire_tv', 'vega', 'tizen', 'webos', 'vidaa', 'tvos', 'roku']);
  });
}
