import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/tv.dart';

import 'tv_presenter_test.dart' show FakePlayer;

// The assistant panel driven only by the remote keys, on the SIMULATED backend. This proves
// the focus and the keys in the Flutter test engine; it does NOT prove a real TV remote.
OryksaTvConfig _cfg({bool phone = true}) => OryksaTvConfig(
      locale: 'pt-PT',
      voiceRev: 'sim-1',
      presenterName: 'ORYKSA',
      presenterAvatar: OryksaTvConfig.defaultAvatar,
      texts: OryksaTvTexts(OryksaTvFakeBackend.sampleTexts['pt-PT']!),
      suggestions: const ['Como funciona?', 'O que podes fazer?'],
      actions: [
        if (phone) const OryksaTvAction(id: 'phone_voice', kind: OryksaTvActionKind.phoneVoice, label: 'Falar pelo telemóvel'),
      ],
      rules: const OryksaTvRules(speakReplies: false),
    );

String? _focusedLabel() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  return ctx.findAncestorWidgetOfExactType<OryksaTvButton>()?.label;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pumpAndSettle();
}

void main() {
  // A TV: 1920x1080 at density 2 (960x540 logical pixels).
  Future<(OryksaTv, OryksaTvFakeBackend)> open(WidgetTester tester, {VoidCallback? onClose, bool phone = true}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final fake = OryksaTvFakeBackend(fixedConfig: _cfg(phone: phone), chatReply: (m) => 'Resposta a: $m');
    final tv = OryksaTv.withBackend(fake, locale: 'pt-PT', audioPlayer: FakePlayer.new);
    await tester.pumpWidget(MaterialApp(home: OryksaTvAssistant(tv: tv, onClose: onClose)));
    await tester.pumpAndSettle();
    return (tv, fake);
  }

  testWidgets('the first question has the focus; the arrows move between the buttons', (tester) async {
    final (tv, _) = await open(tester);
    expect(find.text('(simulado) Fala com a ORYKSA'), findsOneWidget);
    expect(_focusedLabel(), 'Como funciona?');
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedLabel(), 'O que podes fazer?');
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedLabel(), 'Falar pelo telemóvel');
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focusedLabel(), 'O que podes fazer?');
    tv.dispose();
  });

  testWidgets('OK (select) on a question sends it and the reply appears', (tester) async {
    final (tv, fake) = await open(tester);
    await _key(tester, LogicalKeyboardKey.select);
    expect(fake.sentMessages, ['Como funciona?']);
    expect(find.text('Resposta a: Como funciona?'), findsOneWidget);
    expect(find.text('Tu'), findsOneWidget);
    tv.dispose();
  });

  testWidgets('Back calls onClose (the panel inside the app screen)', (tester) async {
    var closed = 0;
    final (tv, _) = await open(tester, onClose: () => closed++);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closed, 1);
    tv.dispose();
  });

  testWidgets('opened as a route, Back closes it and the focus goes back to the app button', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final tv = OryksaTv.withBackend(OryksaTvFakeBackend(fixedConfig: _cfg()), locale: 'pt-PT', audioPlayer: FakePlayer.new);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: OryksaTvButton(label: 'Abrir assistente', autofocus: true, onPressed: () => showOryksaTvAssistant(ctx, tv: tv)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(_focusedLabel(), 'Abrir assistente');
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.byType(OryksaTvAssistant), findsOneWidget);
    expect(_focusedLabel(), 'Como funciona?');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(OryksaTvAssistant), findsNothing);
    expect(_focusedLabel(), 'Abrir assistente');
    tv.dispose();
  });

  testWidgets('the phone button shows the code; what is said on the phone goes to the AI', (tester) async {
    final (tv, fake) = await open(tester);
    tv.phoneVoice.pollWait = const Duration(milliseconds: 50);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedLabel(), 'Falar pelo telemóvel');
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('oryksa-tv-pair-code')), findsOneWidget);
    expect(find.text('K7Q2MZ'), findsWidgets);
    expect(find.text('À espera do telemóvel…'), findsOneWidget);

    fake.phoneConnects();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('Telemóvel ligado'), findsOneWidget);

    fake.phoneSays('Quero ajuda');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(fake.sentMessages, ['Quero ajuda']);
    expect(find.text('Resposta a: Quero ajuda'), findsOneWidget);

    await tv.phoneVoice.stop();
    await tester.pumpAndSettle();
    tv.dispose();
  });

  // With the QR card closed the panel shows where the phone stands (as on Android), in the chosen
  // variant: pt-BR never says "telemóvel", pt-PT never says "celular", and no text key shows raw.
  for (final (locale, phoneButton, connected, left, wrong) in [
    ('pt-PT', 'Falar pelo telemóvel', 'Telemóvel ligado', 'O telemóvel desligou-se', 'celular'),
    ('pt-BR', 'Falar pelo celular', 'Celular conectado', 'O celular desconectou', 'telemóvel'),
  ]) {
    testWidgets('$locale: with the QR card closed the panel shows the phone connected, then the phone leaving', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final cfg = OryksaTvConfig(
        locale: locale,
        voiceRev: 'sim-1',
        presenterName: 'ORYKSA',
        presenterAvatar: OryksaTvConfig.defaultAvatar,
        texts: OryksaTvTexts(OryksaTvFakeBackend.sampleTexts[locale]!),
        suggestions: const [],
        actions: [OryksaTvAction(id: 'phone_voice', kind: OryksaTvActionKind.phoneVoice, label: phoneButton)],
        rules: const OryksaTvRules(speakReplies: false),
      );
      final fake = OryksaTvFakeBackend(fixedConfig: cfg, chatReply: (m) => 'Resposta a: $m');
      final tv = OryksaTv.withBackend(fake, locale: locale, audioPlayer: FakePlayer.new);
      tv.phoneVoice.pollWait = const Duration(milliseconds: 50);
      await tester.pumpWidget(MaterialApp(home: OryksaTvAssistant(tv: tv, onClose: () {})));
      await tester.pumpAndSettle();
      Future<void> settle() async {
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();
      }

      List<String> screen() => tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').toList();
      void rightVariant() {
        for (final s in screen()) {
          expect(s.toLowerCase().contains(wrong), isFalse, reason: '"$s" is not $locale');
          expect(RegExp(r'\b[a-z]+_[a-z_]+\b').hasMatch(s), isFalse, reason: '"$s" is a raw text key');
        }
      }

      String? status() {
        final f = find.byKey(const ValueKey('oryksa-tv-phone-status'));
        return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
      }

      expect(status(), isNull, reason: 'no phone yet: no status line');
      expect(_focusedLabel(), phoneButton);
      await _key(tester, LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('oryksa-tv-pair-code')), findsOneWidget);
      fake.phoneConnects();
      await settle();
      expect(find.text(connected), findsOneWidget, reason: 'the card says it once');
      expect(status(), isNull, reason: 'with the card open the line is not repeated');

      // The phone button again closes the card: the line now says where the phone stands.
      expect(_focusedLabel(), phoneButton);
      await _key(tester, LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('oryksa-tv-pair-code')), findsNothing);
      expect(status(), connected);
      rightVariant();

      fake.phoneSays('Quero ajuda');
      await settle();
      expect(fake.sentMessages, ['Quero ajuda']);
      expect(find.text('Resposta a: Quero ajuda'), findsOneWidget);

      fake.phoneLeaves();
      await settle();
      expect(status(), left);
      rightVariant();

      await tv.phoneVoice.stop();
      await tester.pumpAndSettle();
      tv.dispose();
    });
  }

  testWidgets('typing: closing the keyboard (Back on the Fire TV) never sends; only Send sends', (tester) async {
    final (tv, fake) = await open(tester, phone: false);
    Future<void> openKeyboard() async {
      while (_focusedLabel() != 'Escreve uma mensagem') {
        await _key(tester, LogicalKeyboardKey.arrowRight);
      }
      await _key(tester, LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('oryksa-tv-type-field')), findsOneWidget);
    }

    // The keyboard is closed by the system (what Back does on the Fire TV): focus on Send, nothing sent.
    await openKeyboard();
    await tester.enterText(find.byKey(const ValueKey('oryksa-tv-type-field')), 'Olá TV');
    tester.testTextInput.closeConnection();
    await tester.pumpAndSettle();
    expect(_focusedLabel(), 'Enviar');
    expect(fake.sentMessages, isEmpty);
    // Back on the dialog: closes it without sending.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('oryksa-tv-type-field')), findsNothing);
    expect(fake.sentMessages, isEmpty);

    // The keyboard's own action, then OK on Send: sent.
    await openKeyboard();
    await tester.enterText(find.byKey(const ValueKey('oryksa-tv-type-field')), 'Olá TV');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_focusedLabel(), 'Enviar');
    await _key(tester, LogicalKeyboardKey.select);
    expect(fake.sentMessages, ['Olá TV']);
    expect(find.text('Resposta a: Olá TV'), findsOneWidget);
    tv.dispose();
  });

  testWidgets('the typing dialog has no hidden English label: a screen reader reads the server\'s "close"', (tester) async {
    final semantics = tester.ensureSemantics();
    final (tv, _) = await open(tester, phone: false);
    while (_focusedLabel() != 'Escreve uma mensagem') {
      await _key(tester, LogicalKeyboardKey.arrowRight);
    }
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('oryksa-tv-type-field')), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss'), findsNothing);
    expect(find.bySemanticsLabel('Fechar'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    tv.dispose();
    semantics.dispose();
  });

  testWidgets('without phone voice in the rules there is no phone button', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final cfg = OryksaTvConfig(
      locale: 'pt-PT',
      presenterName: 'ORYKSA',
      presenterAvatar: OryksaTvConfig.defaultAvatar,
      texts: OryksaTvTexts(OryksaTvFakeBackend.sampleTexts['pt-PT']!),
      actions: const [OryksaTvAction(id: 'phone_voice', kind: OryksaTvActionKind.phoneVoice, label: 'Falar pelo telemóvel')],
      rules: const OryksaTvRules(phoneVoice: false, speakReplies: false),
    );
    final tv = OryksaTv.withBackend(OryksaTvFakeBackend(fixedConfig: cfg), locale: 'pt-PT', audioPlayer: FakePlayer.new);
    await tester.pumpWidget(MaterialApp(home: OryksaTvAssistant(tv: tv)));
    await tester.pumpAndSettle();
    expect(find.text('Falar pelo telemóvel'), findsNothing);
    expect(_focusedLabel(), 'Escreve uma mensagem', reason: 'with no questions the first button has the focus');
    tv.dispose();
  });

  for (final k in [LogicalKeyboardKey.select, LogicalKeyboardKey.goBack]) {
    testWidgets('presenter view: ${k.keyLabel} on the remote stops her and the key is not passed on', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final fake = OryksaTvFakeBackend(voice: (t, l) => Uint8List.fromList([0xFF, 0xFB, 1, 2]));
      final tv = OryksaTv.withBackend(fake, locale: 'pt-PT', audioPlayer: () => FakePlayer(playFor: const Duration(seconds: 30)));
      var appGotKey = 0;
      await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
          OryksaTvButton(label: 'Botão da app', autofocus: true, onPressed: () => appGotKey++),
          OryksaPresenterView(tv: tv),
        ]),
      ));
      await tester.pumpAndSettle();
      // The voice cache reads real files: let real time pass between the frames.
      Future<void> settleUntil(bool Function() ok) async {
        for (var i = 0; i < 400 && !ok(); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
          await tester.pump();
        }
      }

      var finished = false;
      unawaited(tv.presenter.say('Olá, sou a ORYKSA ${DateTime.now().microsecondsSinceEpoch}.').then((_) => finished = true));
      await settleUntil(() => tv.presenter.phase == OryksaPresenterPhase.speaking);
      expect(tv.presenter.phase, OryksaPresenterPhase.speaking);
      expect(find.byKey(const ValueKey('oryksa-tv-subtitle')), findsOneWidget);

      // An explicit physical key: the test engine knows no physical key for Go Back
      // (on Android, KEYCODE_BACK arrives as goBack and DPAD_CENTER as select).
      await tester.sendKeyDownEvent(k, physicalKey: PhysicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(k, physicalKey: PhysicalKeyboardKey.escape);
      await settleUntil(() => finished);
      await tester.pump();
      expect(finished, isTrue, reason: 'say() returns when she is stopped');
      expect(tv.presenter.isBusy, isFalse);
      expect(appGotKey, 0, reason: 'the key stopped her and did not press the app button');
      expect(find.byKey(const ValueKey('oryksa-tv-subtitle')), findsNothing);

      // Quiet again: OK goes to the app as usual.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(appGotKey, 1);
      tv.dispose();
    });
  }

  testWidgets('sizes follow the screen: the same at 1080p density 2 and 4K density 4', (tester) async {
    double fontOf() => tester.widget<Text>(find.text('(simulado) Fala com a ORYKSA')).style!.fontSize!;
    final (tv, _) = await open(tester);
    final at1080 = fontOf();
    expect(at1080, closeTo(44 * 540 / 1080, 0.01), reason: '44 px of a 1080p screen');
    tester.view.physicalSize = const Size(3840, 2160);
    tester.view.devicePixelRatio = 4;
    await tester.pumpAndSettle();
    expect(fontOf(), closeTo(at1080, 0.01));
    tv.dispose();
  });
}
