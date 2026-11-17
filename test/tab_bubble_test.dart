import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oryksa/oryksa.dart';

/// The tab bar bubble (1.2): the photo of the AI in the middle of the bar, the
/// chat full screen on phones and as a side panel on wide screens, the
/// microphone that opens the voice screen.
void main() {
  const photo = 'https://app.oryksa.com/static/avatars/sofia.jpg';
  const logo = 'https://app.oryksa.com/static/logos/tugafreela.png';

  /// A client that answers like the ORYKSA API (no network). [launcher] is sent as
  /// `launcher` in the agent (1.2.1); null leaves it out, as an older server.
  OryksaClient fakeClient({bool voice = true, bool agentFails = false, List<Map<String, dynamic>>? sent, Object? launcher, String? openMode = 'chat'}) => OryksaClient(
        token: 'oryk_cs_test',
        httpClient: MockClient((req) async {
          final json = {'content-type': 'application/json; charset=utf-8'};
          switch (req.url.path) {
            case '/v1/client/agent':
              if (agentFails) return http.Response('{"error":{"code":"x","message":"y"}}', 500);
              return http.Response.bytes(
                  utf8.encode(jsonEncode({
                    'name': 'Sofia',
                    'avatar': photo,
                    'business': 'Velas da Sofia',
                    'greeting': {'en': 'Hi! How can I help?', 'pt': 'Olá! Em que posso ajudar?', 'br': 'Oi! Como posso ajudar?'},
                    'voice_replies': voice,
                    if (launcher != null) 'launcher': launcher,
                    if (openMode != null) 'open_mode': openMode, // 1.2.2: null leaves it out (older server: voice)
                  })),
                  200,
                  headers: json);
            case '/v1/client/messages':
              return http.Response('{"messages":[]}', 200, headers: json);
            case '/v1/client/chat':
              sent?.add(jsonDecode(req.body) as Map<String, dynamic>);
              return http.Response.bytes(utf8.encode(jsonEncode({'status': 'replied', 'reply': 'Sim, temos.'})), 200, headers: json);
          }
          return http.Response('{}', 404);
        }),
      );

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget body, {Widget? bar, ThemeData? theme, TextDirection dir = TextDirection.ltr, Locale? locale}) => MaterialApp(
        theme: theme,
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('pt'), Locale('pt', 'BR'), Locale('es')],
        localizationsDelegates: const [_AnyLocale<MaterialLocalizations>(DefaultMaterialLocalizations()),
          _AnyLocale<CupertinoLocalizations>(DefaultCupertinoLocalizations()), _AnyLocale<WidgetsLocalizations>(DefaultWidgetsLocalizations())],
        builder: (context, child) => Directionality(textDirection: dir, child: child!),
        home: Scaffold(body: body, bottomNavigationBar: bar),
      );

  Finder photoOf(String url) => find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url);

  const tabs = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
    NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
    NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
  ];

  group('languages', () {
    test('codes and locale tags map to the 4 SDK languages', () {
      expect(oryksaLang('pt-BR'), 'br');
      expect(oryksaLang('pt_BR'), 'br');
      expect(oryksaLang('br'), 'br');
      expect(oryksaLang('pt-PT'), 'pt');
      expect(oryksaLang('pt'), 'pt');
      expect(oryksaLang('es-ES'), 'es');
      expect(oryksaLang('en-GB'), 'en');
      expect(oryksaLang('fr'), 'en');
      expect(oryksaLang(null), 'en');
      for (final l in ['en', 'pt', 'br', 'es']) {
        expect(oryksaChatTexts(l)['unread'], isNotEmpty);
        expect(oryksaVoiceTexts(l)['listening'], isNotEmpty);
      }
    });
  });

  group('OryksaTabBubble', () {
    testWidgets('shows the photo of the AI and says who it is', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(), lang: 'en'))));
      await tester.pumpAndSettle();
      expect(photoOf(photo), findsOneWidget);
      expect(find.bySemanticsLabel('Talk to Sofia'), findsOneWidget);
      expect(find.byKey(const ValueKey('oryksa-unread-dot')), findsNothing);
      expect(tester.getSize(find.byType(OryksaTabBubble)), const Size(64, 64));
      handle.dispose();
    });

    testWidgets('unread dot, with the label in the app language (pt-BR)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(), unread: true, showLabel: true)),
          locale: const Locale('pt', 'BR')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('oryksa-unread-dot')), findsOneWidget);
      expect(find.bySemanticsLabel('Falar com Sofia, nova mensagem'), findsOneWidget);
      expect(find.text('Sofia'), findsOneWidget); // name under the bubble
      handle.dispose();
    });

    testWidgets('when the agent cannot load it still shows a bubble and opens the chat', (tester) async {
      final handle = tester.ensureSemantics();
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(agentFails: true), lang: 'es'))));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Hablar con ORYKSA'), findsOneWidget);
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(find.byType(OryksaChat), findsOneWidget);
      handle.dispose();
    });

    testWidgets('phone: tapping opens the chat full screen; close goes back', (tester) async {
      await setSize(tester, const Size(400, 800));
      var opened = 0;
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(), lang: 'pt', onOpen: () => opened++))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(OryksaChat), findsOneWidget);
      expect(tester.getSize(find.byType(OryksaChat)).width, 400); // the whole width
      expect(find.text('SOFIA'), findsOneWidget);
      expect(find.text('Olá! Em que posso ajudar?'), findsOneWidget);
      expect(find.byTooltip('Falar por voz'), findsOneWidget); // the microphone
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(OryksaChat), findsNothing);
    });

    testWidgets('wide screen (840 dp or more): side panel at the end, the app stays visible', (tester) async {
      await setSize(tester, const Size(1280, 800));
      await tester.pumpWidget(app(const Center(child: Text('My app')), bar: OryksaBottomBar(client: fakeClient(), lang: 'en', selectedIndex: 0, onDestinationSelected: (_) {}, destinations: tabs)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      final panel = find.byType(OryksaChat);
      expect(panel, findsOneWidget);
      expect(tester.getSize(panel).width, 420);
      expect(tester.getTopRight(panel).dx, 1280); // at the right edge
      expect(find.text('My app'), findsOneWidget);
      await tester.tapAt(const Offset(200, 300)); // outside the panel closes it
      await tester.pumpAndSettle();
      expect(find.byType(OryksaChat), findsNothing);
    });

    testWidgets('right-to-left app: the side panel opens on the left', (tester) async {
      await setSize(tester, const Size(1024, 768));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(), lang: 'en')), dir: TextDirection.rtl));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(OryksaChat)).dx, 0);
    });

    testWidgets('dark app: the chat opens with the dark colors', (tester) async {
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(), lang: 'en')), theme: ThemeData(brightness: Brightness.dark)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      final m = tester.widget<Material>(find.descendant(of: find.byType(OryksaChat), matching: find.byType(Material)).first);
      expect(m.color, const OryksaChatTheme.dark().background);
    });

    testWidgets('the chat sends the language of the app with each message', (tester) async {
      await setSize(tester, const Size(400, 800));
      final sent = <Map<String, dynamic>>[];
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(sent: sent), lang: 'pt-BR'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tem vela de lavanda?');
      await tester.tap(find.text('ENVIAR'));
      await tester.pumpAndSettle();
      expect(sent.single['message'], 'Tem vela de lavanda?');
      expect(sent.single['lang'], 'br');
      expect(find.text('Sim, temos.'), findsOneWidget);
    });
  });

  group('OryksaBottomBar', () {
    testWidgets('the bubble is in the middle of the destinations', (tester) async {
      await setSize(tester, const Size(400, 800));
      final handle = tester.ensureSemantics();
      final picked = <int>[];
      await tester.pumpWidget(app(const SizedBox(),
          bar: OryksaBottomBar(client: fakeClient(), lang: 'en', selectedIndex: 1, onDestinationSelected: picked.add, destinations: tabs)));
      await tester.pumpAndSettle();
      final bubble = tester.getCenter(find.byType(OryksaTabBubble)).dx;
      expect(bubble, closeTo(200, .01));
      expect(tester.getCenter(find.text('Home')).dx, lessThan(bubble));
      expect(tester.getCenter(find.text('Search')).dx, lessThan(bubble));
      expect(tester.getCenter(find.text('Orders')).dx, greaterThan(bubble));
      expect(tester.getCenter(find.text('Profile')).dx, greaterThan(bubble));
      // the bubble rises above the bar
      expect(tester.getTopLeft(find.byType(OryksaTabBubble)).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('oryksa-tab-0'))).dy));
      expect(find.text('Sofia'), findsOneWidget); // the AI name under the bubble
      await tester.tap(find.text('Orders'));
      expect(picked, [2]);
      final search = tester.getSemantics(find.byKey(const ValueKey('oryksa-tab-1')));
      expect(search.label, contains('Search'));
      expect(search, isSemantics(isSelected: true, isButton: true));
      expect(tester.getSemantics(find.byKey(const ValueKey('oryksa-tab-0'))), isSemantics(isSelected: false, isButton: true));
      handle.dispose();
    });

    testWidgets('odd number of destinations: the extra one goes before the bubble', (tester) async {
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(const SizedBox(),
          bar: OryksaBottomBar(client: fakeClient(), lang: 'en', selectedIndex: 0, onDestinationSelected: (_) {}, destinations: tabs.sublist(0, 3))));
      await tester.pumpAndSettle();
      final bubble = tester.getCenter(find.byType(OryksaTabBubble)).dx;
      expect(tester.getCenter(find.text('Search')).dx, lessThan(bubble));
      expect(tester.getCenter(find.text('Orders')).dx, greaterThan(bubble));
    });

    testWidgets('bar bubble opens the chat; onBubbleTap replaces it', (tester) async {
      await setSize(tester, const Size(400, 800));
      var custom = 0;
      await tester.pumpWidget(app(const SizedBox(),
          bar: OryksaBottomBar(client: fakeClient(), lang: 'en', selectedIndex: 0, onDestinationSelected: (_) {}, destinations: tabs, onBubbleTap: () => custom++)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(custom, 1);
      expect(find.byType(OryksaChat), findsNothing);

      await tester.pumpWidget(app(const SizedBox(),
          bar: OryksaBottomBar(client: fakeClient(), lang: 'en', selectedIndex: 0, onDestinationSelected: (_) {}, destinations: tabs)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(find.byType(OryksaChat), findsOneWidget);
    });

    testWidgets('safe area: the bar grows by the bottom inset', (tester) async {
      await setSize(tester, const Size(400, 800));
      tester.view.padding = const FakeViewPadding(bottom: 34);
      await tester.pumpWidget(app(const SizedBox(),
          bar: OryksaBottomBar(client: fakeClient(), lang: 'en', selectedIndex: 0, onDestinationSelected: (_) {}, destinations: tabs)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(OryksaBottomBar)).height, 14 + 80 + 34);
    });
  });

  /// The company logo in the bubble (1.2.1): the business picks it in the ORYKSA
  /// panel, the bubble shows it whole with the business name, the chat keeps the AI.
  group('bubble image (1.2.1)', () {
    const tuga = {'icon': 'logo', 'image': logo, 'label': 'TugaFreela'};
    Finder inBubble(Finder f) => find.descendant(of: find.byType(OryksaTabBubble), matching: f);
    Finder inChat(Finder f) => find.descendant(of: find.byType(OryksaChat), matching: f);
    final white = find.byWidgetPredicate((w) => w is ColoredBox && w.color == Colors.white);
    // The room around a logo: 12% of the photo inside the ring (64 dp bubble).
    const size = 64.0;
    const pad = (size - 2 * (size * .065 + size * .05)) * .12;
    // A 1x1 PNG, as an image of the app.
    final mine = MemoryImage(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));

    testWidgets('company logo from the panel: the whole logo, the business name under it, the chat keeps the AI', (tester) async {
      final handle = tester.ensureSemantics();
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(launcher: tuga), lang: 'en', showLabel: true))));
      await tester.pump(); // the agent arrives; the logo is still loading
      expect(photoOf(logo), findsOneWidget);
      expect(tester.widget<Image>(photoOf(logo)).fit, BoxFit.contain);
      expect(photoOf(photo), findsNothing);
      expect(inBubble(white), findsOneWidget); // on white
      expect(tester.widget<Padding>(find.descendant(of: inBubble(white), matching: find.byType(Padding)).first).padding, const EdgeInsets.all(pad));
      await tester.pumpAndSettle();
      expect(find.text('TugaFreela'), findsOneWidget);
      expect(find.text('Sofia'), findsNothing);
      expect(find.bySemanticsLabel('Talk to Sofia'), findsOneWidget); // the chat opens with the AI
      expect(tester.widget<Tooltip>(inBubble(find.byType(Tooltip))).message, 'Talk to Sofia');

      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(find.byType(OryksaChat), findsOneWidget);
      expect(find.text('SOFIA'), findsOneWidget);
      expect(inChat(photoOf(photo)), findsWidgets);
      expect(inChat(photoOf(logo)), findsNothing);
      expect(inChat(find.text('TugaFreela')), findsNothing);
      handle.dispose();
    });

    testWidgets('older server without launcher: the photo of the AI and its name, as 1.2.0', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(), lang: 'en', showLabel: true))));
      await tester.pump();
      expect(photoOf(photo), findsOneWidget);
      expect(tester.widget<Image>(photoOf(photo)).fit, BoxFit.cover);
      expect(inBubble(white), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Sofia'), findsOneWidget);
      expect(find.bySemanticsLabel('Talk to Sofia'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('launcher "ai", or "logo" with no image: the photo of the AI', (tester) async {
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(
          client: fakeClient(launcher: {'icon': 'ai', 'image': 'https://app.oryksa.com/static/avatars/other.jpg', 'label': 'Sofia'}), lang: 'en', showLabel: true))));
      await tester.pump();
      expect(tester.widget<Image>(photoOf(photo)).fit, BoxFit.cover);
      expect(inBubble(white), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Sofia'), findsOneWidget);

      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(launcher: {'icon': 'logo', 'label': 'TugaFreela'}), lang: 'en', showLabel: true))));
      await tester.pump();
      expect(tester.widget<Image>(photoOf(photo)).fit, BoxFit.cover);
      expect(inBubble(white), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('TugaFreela'), findsOneWidget);
    });

    testWidgets('image: of the app wins over the logo of the panel', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(launcher: tuga), lang: 'en', showLabel: true, image: mine))));
      await tester.pumpAndSettle();
      final img = tester.widget<Image>(inBubble(find.byType(Image)));
      expect(img.image, same(mine));
      expect(img.fit, BoxFit.contain);
      expect(photoOf(logo), findsNothing);
      expect(photoOf(photo), findsNothing);
      expect(inBubble(white), findsOneWidget);
      expect(tester.widget<Padding>(find.descendant(of: inBubble(white), matching: find.byType(Padding)).first).padding, const EdgeInsets.all(pad));
      expect(find.text('TugaFreela'), findsOneWidget);
      expect(find.bySemanticsLabel('Talk to Sofia'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('image: also wins over the photo of the AI, and shows before the agent loads', (tester) async {
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(agentFails: true), lang: 'en', image: mine))));
      expect(tester.widget<Image>(inBubble(find.byType(Image))).image, same(mine));
      await tester.pumpAndSettle();
      expect(tester.widget<Image>(inBubble(find.byType(Image))).image, same(mine));
      expect(photoOf(photo), findsNothing);
    });

    testWidgets('label: wins over the label of the panel', (tester) async {
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(launcher: tuga), lang: 'en', showLabel: true, label: 'Help'))));
      await tester.pumpAndSettle();
      expect(find.text('Help'), findsOneWidget);
      expect(find.text('TugaFreela'), findsNothing);
      expect(find.text('Sofia'), findsNothing);
    });

    testWidgets('a logo that does not load falls back to the placeholder', (tester) async {
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(launcher: tuga), lang: 'en'))));
      await tester.pumpAndSettle(); // the test has no network: the logo fails
      expect(inBubble(find.byIcon(Icons.chat_bubble_rounded)), findsOneWidget);
      expect(inBubble(white), findsNothing);
    });

    testWidgets('OryksaBottomBar: the panel logo and name, bubbleImage and bubbleLabel', (tester) async {
      await setSize(tester, const Size(400, 800));
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const SizedBox(),
          bar: OryksaBottomBar(client: fakeClient(launcher: tuga), lang: 'en', selectedIndex: 0, onDestinationSelected: (_) {}, destinations: tabs)));
      await tester.pump();
      expect(tester.widget<Image>(photoOf(logo)).fit, BoxFit.contain);
      await tester.pumpAndSettle();
      expect(find.text('TugaFreela'), findsOneWidget);
      expect(find.bySemanticsLabel('Talk to Sofia'), findsOneWidget);

      await tester.pumpWidget(app(const SizedBox(),
          bar: OryksaBottomBar(
              client: fakeClient(launcher: tuga), lang: 'en', selectedIndex: 0, onDestinationSelected: (_) {}, destinations: tabs, bubbleImage: mine, bubbleLabel: 'Help')));
      await tester.pumpAndSettle();
      expect(tester.widget<OryksaTabBubble>(find.byType(OryksaTabBubble)).image, same(mine));
      expect(tester.widget<Image>(inBubble(find.byType(Image))).image, same(mine));
      expect(photoOf(logo), findsNothing);
      expect(find.text('Help'), findsOneWidget);
      expect(find.text('TugaFreela'), findsNothing);
      expect(find.bySemanticsLabel('Talk to Sofia'), findsOneWidget);
      handle.dispose();
    });
  });

  group('OryksaAgent launcher (1.2.1)', () {
    OryksaAgent parse(Object? launcher) => OryksaAgent.fromJson({'name': 'Manuel', 'avatar': photo, if (launcher != null) 'launcher': launcher});

    test('reads the launcher of the agent', () {
      final logoAgent = parse({'icon': 'logo', 'image': logo, 'label': 'TugaFreela'});
      expect(logoAgent.launcherIcon, 'logo');
      expect(logoAgent.launcherImage, logo);
      expect(logoAgent.launcherLabel, 'TugaFreela');
      expect(logoAgent.name, 'Manuel'); // the chat keeps the AI
      expect(logoAgent.avatar, photo);

      final aiAgent = parse({'icon': 'ai', 'image': photo, 'label': 'Manuel'});
      expect(aiAgent.launcherIcon, 'ai');
      expect(aiAgent.launcherImage, photo);
      expect(aiAgent.launcherLabel, 'Manuel');

      // the whole JSON as it comes from the server
      final fromServer = OryksaAgent.fromJson(jsonDecode(jsonEncode({'name': 'Manuel', 'avatar': photo, 'launcher': {'icon': 'logo', 'image': logo, 'label': 'TugaFreela'}})) as Map<String, dynamic>);
      expect(fromServer.launcherIcon, 'logo');
      expect(fromServer.launcherImage, logo);
      expect(fromServer.launcherLabel, 'TugaFreela');
    });

    test('no launcher (older server): the defaults of 1.2.0', () {
      final a = parse(null);
      expect(a.launcherIcon, 'ai');
      expect(a.launcherImage, isNull);
      expect(a.launcherLabel, isNull);
      const b = OryksaAgent(name: 'Manuel', avatar: photo); // the const constructor still works
      expect(b.launcherIcon, 'ai');
      expect(b.launcherImage, isNull);
      expect(b.launcherLabel, isNull);
    });

    test('survives garbage', () {
      for (final bad in <Object>['logo', 42, true, ['logo', logo], <String, dynamic>{}]) {
        final a = parse(bad);
        expect(a.launcherIcon, 'ai', reason: '$bad');
        expect(a.launcherImage, isNull, reason: '$bad');
        expect(a.launcherLabel, isNull, reason: '$bad');
        expect(a.name, 'Manuel');
      }
      final noImage = parse({'icon': 'logo', 'label': 'TugaFreela'});
      expect(noImage.launcherIcon, 'logo');
      expect(noImage.launcherImage, isNull);
      expect(noImage.launcherLabel, 'TugaFreela');

      final wrongTypes = parse({'icon': 7, 'image': 3.5, 'label': ['x']});
      expect(wrongTypes.launcherIcon, 'ai');
      expect(wrongTypes.launcherImage, isNull);
      expect(wrongTypes.launcherLabel, isNull);

      final blanks = parse({'icon': ' LOGO ', 'image': '   ', 'label': ''});
      expect(blanks.launcherIcon, 'logo');
      expect(blanks.launcherImage, isNull);
      expect(blanks.launcherLabel, isNull);

      final nulls = parse({'icon': null, 'image': null, 'label': null});
      expect(nulls.launcherIcon, 'ai');
      expect(nulls.launcherImage, isNull);
      expect(nulls.launcherLabel, isNull);

      expect(parse({'icon': 'banana', 'image': logo}).launcherIcon, 'ai');
      expect(parse({'image': logo}).launcherIcon, 'ai');
    });
  });

  group('voice from the chat', () {
    setUp(() {
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final ch in [
        'com.llfbandit.record/messages',
        'com.ryanheise.just_audio.methods',
        'com.ryanheise.audio_session',
        'com.ryanheise.av_audio_session',
        'com.ryanheise.android_audio_manager',
      ]) {
        m.setMockMethodCallHandler(MethodChannel(ch), (call) async {
          if (call.method == 'hasPermission') return false; // no microphone in the test
          if (ch == 'com.ryanheise.just_audio.methods') return <String, dynamic>{};
          return null;
        });
      }
    });

    testWidgets('1.2.2: the panel says voice (also the default): the bubble opens straight in the voice screen', (tester) async {
      for (final mode in <String?>['voice', null]) {
        await setSize(tester, const Size(400, 800));
        await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(openMode: mode), lang: 'en'))));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(OryksaTabBubble));
        for (var i = 0; i < 30 && find.byType(OryksaVoiceScreen).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(OryksaVoiceScreen), findsOneWidget, reason: 'open_mode=$mode, chat=${find.byType(OryksaChat).evaluate().length}');
        await tester.tap(find.descendant(of: find.byType(OryksaVoiceScreen), matching: find.byTooltip('Close')).first);
        for (var i = 0; i < 20 && find.byType(OryksaVoiceScreen).evaluate().isNotEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(OryksaVoiceScreen), findsNothing);
        expect(find.byType(OryksaChat), findsOneWidget); // closing the voice leaves the customer in the chat
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
      }
    });

    testWidgets('1.2.2: the panel says chat: the bubble opens the text chat', (tester) async {
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(openMode: 'chat'), lang: 'en'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(find.byType(OryksaChat), findsOneWidget);
      expect(find.byType(OryksaVoiceScreen), findsNothing);
    });

    testWidgets('1.2.2: voice mode but the plan has no voice: the text chat', (tester) async {
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(openMode: 'voice', voice: false), lang: 'en'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(find.byType(OryksaChat), findsOneWidget);
      expect(find.byType(OryksaVoiceScreen), findsNothing);
    });

    testWidgets('the microphone in the chat opens the voice screen', (tester) async {
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(), lang: 'en'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Talk by voice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(OryksaVoiceScreen), findsOneWidget);
      expect(find.text('Microphone unavailable'), findsOneWidget); // the test has no microphone
      await tester.tap(find.byTooltip('Close').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(OryksaVoiceScreen), findsNothing);
      expect(find.byType(OryksaChat), findsOneWidget); // back in the chat
    });

    testWidgets('with the company logo in the bubble, the voice screen keeps the photo and name of the AI', (tester) async {
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(
          client: fakeClient(launcher: {'icon': 'logo', 'image': logo, 'label': 'TugaFreela'}), lang: 'en', showLabel: true))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Talk by voice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final voiceScreen = find.byType(OryksaVoiceScreen);
      expect(voiceScreen, findsOneWidget);
      expect(find.descendant(of: voiceScreen, matching: photoOf(photo)), findsWidgets);
      expect(find.descendant(of: voiceScreen, matching: photoOf(logo)), findsNothing);
      expect(find.descendant(of: voiceScreen, matching: find.text('Sofia')), findsOneWidget);
      expect(find.descendant(of: voiceScreen, matching: find.text('TugaFreela')), findsNothing);
      await tester.tap(find.byTooltip('Close').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(OryksaVoiceScreen), findsNothing);
    });

    testWidgets('no microphone when the plan has no voice', (tester) async {
      await setSize(tester, const Size(400, 800));
      await tester.pumpWidget(app(Center(child: OryksaTabBubble(client: fakeClient(voice: false), lang: 'en'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OryksaTabBubble));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Talk by voice'), findsNothing);
    });
  });
  group('1.2.2 models', () {
    test('open_mode: voice by default, chat when the panel says so', () {
      expect(OryksaAgent.fromJson({'name': 'Manuel', 'avatar': photo}).openMode, 'voice');
      expect(OryksaAgent.fromJson({'name': 'Manuel', 'avatar': photo, 'open_mode': 'chat'}).openMode, 'chat');
      expect(OryksaAgent.fromJson({'name': 'Manuel', 'avatar': photo, 'open_mode': 'xyz'}).openMode, 'voice');
    });
    test('collecting: the detail the AI is asking for', () {
      expect(OryksaReply.fromJson({'status': 'replied', 'reply': 'O teu email?', 'collecting': 'email'}).collecting, 'email');
      expect(OryksaReply.fromJson({'status': 'replied', 'reply': 'Olá'}).collecting, isNull);
      expect(OryksaReply.fromJson({'status': 'replied', 'reply': 'Olá', 'collecting': ''}).collecting, isNull);
    });
  });
}

/// The English texts of Flutter for any locale (a real app adds flutter_localizations);
/// the ORYKSA texts still follow the locale.
class _AnyLocale<T> extends LocalizationsDelegate<T> {
  const _AnyLocale(this.value);
  final T value;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => SynchronousFuture<T>(value);

  @override
  bool shouldReload(_AnyLocale<T> old) => false;
}
