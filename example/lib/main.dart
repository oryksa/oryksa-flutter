// ORYKSA in a Flutter app: the AI bubble in the middle of the tab bar, the chat
// and the voice.
//
// Your server creates a session token for the signed-in user with the secret key
// (POST https://api.oryksa.com/v1/sessions) and returns only `client_token`.
// The app never contains the secret key.
//
// Voice: add the microphone permission to your app
//   Android  android/app/src/main/AndroidManifest.xml
//            <uses-permission android:name="android.permission.RECORD_AUDIO"/>
//   iOS      ios/Runner/Info.plist
//            <key>NSMicrophoneUsageDescription</key><string>To talk to our assistant.</string>
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:oryksa/oryksa.dart';

import 'theme_example.dart';

/// Your backend endpoint that returns {"token": "oryk_cs_..."} for the signed-in user.
const tokenEndpoint = String.fromEnvironment('ORYKSA_TOKEN_URL', defaultValue: 'https://your-server.example/oryksa-token');

/// Only for local tests: a session token passed with --dart-define (never the secret key).
const testToken = String.fromEnvironment('ORYKSA_TEST_TOKEN');

/// Reads a --dart-define value; on the web also `?name=` in the address (used by the CI screenshots).
String _arg(String name, String fromEnv) => fromEnv.isNotEmpty ? fromEnv : (Uri.base.queryParameters[name] ?? '');

/// `en`, `pt`, `br` or `es`. Empty: the language of the phone.
final lang = _arg('lang', const String.fromEnvironment('ORYKSA_LANG'));

/// Only for the CI: `chat` or `theme` opens the chat panel directly, `voice` the voice
/// conversation (audio route check). Empty: the app.
final screen = _arg('screen', const String.fromEnvironment('ORYKSA_SCREEN'));

Future<String> fetchSessionToken() async {
  if (testToken.isNotEmpty) return testToken;
  final r = await http.get(Uri.parse(tokenEndpoint));
  return (jsonDecode(r.body) as Map<String, dynamic>)['token'] as String;
}

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ORYKSA SDK demo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF5B57E0)),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF5B57E0), brightness: Brightness.dark),
        // With these the bubble and the chat follow the language of the phone.
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('pt'), Locale('pt', 'BR'), Locale('es')],
        home: screen.isEmpty ? const Shell() : (screen == 'say' ? const SayScreen() : const ChatScreen()),
      );
}

const _texts = {
  'en': ['My store', 'Shop', 'Search', 'Orders', 'Account', 'Add to cart'],
  'pt': ['A minha loja', 'Loja', 'Procurar', 'Encomendas', 'Conta', 'Adicionar ao carrinho'],
  'br': ['Minha loja', 'Loja', 'Buscar', 'Pedidos', 'Conta', 'Adicionar ao carrinho'],
  'es': ['Mi tienda', 'Tienda', 'Buscar', 'Pedidos', 'Cuenta', 'Añadir al carrito'],
};

/// The app: four tabs and the AI bubble in the middle of the bar.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final client = OryksaClient(getToken: fetchSessionToken);
  int tab = 0;

  /// What the customer sees now, so the AI answers about it.
  OryksaAppContext appContext() => tab == 0
      ? const OryksaAppContext(
          screen: 'product',
          title: 'Sky Beginner Snowboard, 489.95',
          items: ['Sky Beginner Snowboard', 'Pro Glide Snowboard Wax'],
        )
      : OryksaAppContext(screen: ['shop', 'search', 'orders', 'account'][tab]);

  @override
  Widget build(BuildContext context) {
    final t = _texts[oryksaLangOf(context, lang.isEmpty ? null : lang)]!;
    return Scaffold(
      appBar: AppBar(title: Text(t[0])),
      body: IndexedStack(index: tab, children: [
        ProductPage(cta: t[5]),
        Center(child: Icon(Icons.search, size: 64, color: Theme.of(context).colorScheme.outline)),
        Center(child: Icon(Icons.receipt_long_outlined, size: 64, color: Theme.of(context).colorScheme.outline)),
        Center(child: Icon(Icons.person_outline, size: 64, color: Theme.of(context).colorScheme.outline)),
      ]),
      // The ORYKSA bubble in the middle of the bar. Same items as a NavigationBar.
      bottomNavigationBar: OryksaBottomBar(
        client: client,
        lang: lang.isEmpty ? null : lang,
        appContext: appContext,
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.storefront_outlined), selectedIcon: const Icon(Icons.storefront), label: t[1]),
          NavigationDestination(icon: const Icon(Icons.search), label: t[2]),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: t[3]),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t[4]),
        ],
      ),
    );
  }
}

/// A product page of your app. The chat knows the customer is looking at it.
/// On wide screens (tablets, foldables) the picture and the details sit side by side.
class ProductPage extends StatelessWidget {
  const ProductPage({super.key, required this.cta});
  final String cta;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final picture = AspectRatio(
      aspectRatio: 1.5,
      child: DecoratedBox(
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
        child: Icon(Icons.snowboarding, size: 96, color: cs.primary),
      ),
    );
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Sky Beginner Snowboard', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('489.95', style: text.titleLarge),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add_shopping_cart), label: Text(cta)),
    ]);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 700) {
        return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [picture, const SizedBox(height: 16), details]);
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: picture),
              const SizedBox(width: 32),
              Expanded(child: details),
            ]),
          ),
        ),
      );
    });
  }
}


/// The chat panel on its own (CI screenshots): default colors for `chat`, the README theme for `theme`.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final client = OryksaClient(getToken: fetchSessionToken);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: OryksaChat(
            client: client,
            lang: lang.isEmpty ? 'en' : lang,
            theme: screen == 'theme' ? readmeTheme : const OryksaChatTheme(),
            startInVoice: screen == 'voice',
            appContext: () => const OryksaAppContext(
              screen: 'product',
              title: 'Sky Beginner Snowboard, 489.95',
              items: ['Sky Beginner Snowboard'],
            ),
          ),
        ),
      );
}


/// Only for the CI audio route check (`say`): the AI's voice says one sentence, so the
/// emulator can show where Android plays it (the CI emulator has no microphone).
class SayScreen extends StatefulWidget {
  const SayScreen({super.key});

  @override
  State<SayScreen> createState() => _SayScreenState();
}

class _SayScreenState extends State<SayScreen> {
  late final voice = OryksaVoiceController(client: OryksaClient(getToken: fetchSessionToken), lang: 'pt');

  @override
  void initState() {
    super.initState();
    () async {
      await voice.start();
      await voice.say('Olá! Isto é um teste do altifalante da voz no Android. Estás a ouvir-me bem alto e claro?');
    }();
  }

  @override
  void dispose() {
    voice.close();
    voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: AnimatedBuilder(animation: voice, builder: (_, __) => Text('voice: ${voice.phase.name}')),
        ),
      );
}
