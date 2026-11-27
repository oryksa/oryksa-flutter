import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oryksa/tv.dart';
import 'package:oryksa_tv_demo/main.dart';
import 'package:oryksa_tv_demo/strings.dart';

void main() {
  testWidgets('the demo starts in the device language (en-US here), says it is simulated, and OK opens the assistant',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final tv = OryksaTv.withBackend(OryksaTvFakeBackend(), locale: 'en-US');
    await tester.pumpWidget(DemoApp(tv: tv));
    await tester.pumpAndSettle();
    expect(find.text('Simulated demo: it does not use the ORYKSA server'), findsOneWidget);
    expect(find.text('Language: English (US)'), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<OryksaTvButton>();
    expect(focused?.label, 'Hear the host');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(OryksaTvAssistant), findsOneWidget);
  });

  testWidgets('"Change the language" changes the whole screen at once (pt-BR then pt-PT)', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.localeTestValue = const Locale('pt', 'BR');
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final tv = OryksaTv.withBackend(OryksaTvFakeBackend(), locale: 'pt-BR');
    await tester.pumpWidget(DemoApp(tv: tv));
    await tester.pumpAndSettle();
    expect(find.text('Idioma: Português (Brasil)'), findsOneWidget);
    expect(find.text('Falar pelo celular'), findsOneWidget);
    expect(find.textContaining('telemóvel'), findsNothing);

    // "Mudar o idioma" (tapped: the wide test font wraps the buttons, so the arrows are not the point here).
    await tester.tap(find.text('Mudar o idioma'));
    await tester.pumpAndSettle();
    expect(find.text('Língua: Português (Portugal)'), findsOneWidget);
    expect(find.text('Falar pelo telemóvel'), findsOneWidget);
    expect(find.textContaining('celular'), findsNothing);
    expect(find.text('Mudar a língua'), findsOneWidget);
  });

  testWidgets('the QR dialog has no hidden English label: a screen reader reads the server\'s "close" (pt-BR)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.localeTestValue = const Locale('pt', 'BR');
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final tv = OryksaTv.withBackend(OryksaTvFakeBackend(), locale: 'pt-BR');
    await tester.pumpWidget(DemoApp(tv: tv));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Falar pelo celular'));
    await tester.pumpAndSettle();
    expect(find.byType(OryksaPairingCard), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss'), findsNothing);
    expect(find.bySemanticsLabel('Fechar'), findsOneWidget);
    await tv.phoneVoice.stop();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  test('the device language picks the first language: one of the 8, otherwise English of the USA', () {
    expect(demoInitialLocale('pt-BR'), 'pt-BR');
    expect(demoInitialLocale('pt-AO'), 'pt-PT');
    expect(demoInitialLocale('es-AR'), 'es-MX');
    expect(demoInitialLocale('es-ES'), 'es-ES');
    expect(demoInitialLocale('it-IT'), 'en-US');
    expect(demoInitialLocale('ja'), 'en-US');
  });

  test('no word of the wrong variant in any text of the demo or of the simulated backend (automatic search)', () {
    final problems = <String>[];
    void scan(String table, String where, Iterable<String> texts) {
      for (final word in demoForbiddenWords[table] ?? const <String>[]) {
        final re = RegExp('(^|[^\\p{L}])${RegExp.escape(word)}(\$|[^\\p{L}])', caseSensitive: false, unicode: true);
        for (final t in texts) {
          if (re.hasMatch(t)) problems.add('$where [$table] "$word" in: $t');
        }
      }
    }

    for (final e in demoTables.entries) {
      scan(e.key, 'demo', e.value.values);
    }
    for (final locale in ['pt-BR', 'pt-PT', 'es-MX', 'es-ES']) {
      final table = OryksaTvFakeBackend.resolveLocale(locale);
      scan(table, 'simulated backend', OryksaTvFakeBackend.sampleTextsFor(table).values);
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
    // Every table has every key of the US English one.
    for (final e in demoTables.entries) {
      expect(e.value.keys.toSet(), demoTables['en-US']!.keys.toSet(), reason: e.key);
    }
  });
}
