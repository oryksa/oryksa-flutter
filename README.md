<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# oryksa

Official Flutter SDK for **ORYKSA AI Employees**. Put an AI employee that already knows your business inside your Flutter app (Android, iOS, web and desktop): a round bubble with the photo of your AI in the middle of your tab bar, a ready chat with the same look as the ORYKSA website chat, the name and photo of your AI from your ORYKSA account, in English, Portuguese (Portugal and Brazil) and Spanish.

* Docs: https://developer.oryksa.com/en/sdks
* API: `https://api.oryksa.com/v1`

**Read in:** English (this page), or open your language:

<details>
<summary><b>Português</b></summary>

SDK oficial Flutter da **ORYKSA AI Employees**: põe na tua app um colaborador de IA que já conhece o teu negócio, com um chat pronto igual ao chat do site da ORYKSA, com o nome e a foto da tua IA.

1. O teu **servidor** guarda a chave secreta e cria um token de sessão para cada utilizador (`POST /v1/sessions`).
2. A **app** usa só esse token: `OryksaClient(getToken: ...)` e `OryksaChatButton(client: client, lang: 'pt')`.
3. **Bolinha na barra de separadores (1.2):** troca o teu `NavigationBar` por `OryksaBottomBar(client: client, ...)` e a foto da tua IA fica no meio da barra. Ao tocar abre o chat com voz: ecrã inteiro no telemóvel, painel lateral em ecrãs largos. Numa barra tua, usa `OryksaTabBubble(client: client)`.
4. Cada resposta da IA conta como uma interação do teu plano.
5. As funções de servidor (chave secreta, alterar a IA e o Brain, webhooks) estão numa biblioteca à parte, `package:oryksa/oryksa_server.dart`, só para o teu servidor. Nunca a importes na app.

</details>

<details>
<summary><b>Español</b></summary>

SDK oficial de Flutter de **ORYKSA AI Employees**: pon en tu app un empleado de IA que ya conoce tu negocio, con un chat listo igual al chat de la web de ORYKSA, con el nombre y la foto de tu IA.

1. Tu **servidor** guarda la clave secreta y crea un token de sesión para cada usuario (`POST /v1/sessions`).
2. La **app** usa solo ese token: `OryksaClient(getToken: ...)` y `OryksaChatButton(client: client, lang: 'es')`.
3. **Burbuja en la barra de pestañas (1.2):** cambia tu `NavigationBar` por `OryksaBottomBar(client: client, ...)` y la foto de tu IA queda en el centro de la barra. Al tocarla se abre el chat con voz: pantalla completa en el móvil, panel lateral en pantallas anchas. En una barra propia, usa `OryksaTabBubble(client: client)`.
4. Cada respuesta de la IA cuenta como una interacción de tu plan.
5. Las funciones de servidor (clave secreta, cambiar la IA y el Brain, webhooks) están en una biblioteca aparte, `package:oryksa/oryksa_server.dart`, solo para tu servidor. Nunca la importes en la app.

</details>

## Install

```bash
flutter pub add oryksa
```

## What it is for

The SDK puts the ORYKSA chat and voice inside your app to serve the **customers of your business**: they ask, buy and book. The AI answers with your Brain, products and services, with the name, photo and voice you chose in *Your AI*, and saves leads, bookings and sales in the Activities of your ORYKSA account. It is **not** an interface for the owner: nobody changes settings, reads Activities or gives orders to ORYKSA through the SDK. More: https://help.oryksa.com/en/a/sdks-what-they-do

Swear words the customer types show as asterisks in the chat (the same list as every ORYKSA chat, loaded from `https://app.oryksa.com/widget/profanity.json`, kept 24 hours). The AI's replies already come filtered from the server.

## Tab bar bubble (1.2)

The round bubble with the photo of your AI in the middle of the bottom tab bar, the same as in the ORYKSA app. Tapping it opens the chat (with the microphone for voice): full screen on phones, a side panel on wide screens (840 dp or more: tablets, open foldables, desktop), so your app stays visible beside it. The name and photo come from *Your AI* in your ORYKSA account.

<p align="center"><img src="https://developer.oryksa.com/assets/img/sdk/flutter-tab-bubble.png" width="760" alt="ORYKSA tab bar bubble: the bar, the chat, the voice screen and the side panel on a tablet"></p>

Swap your `NavigationBar` for `OryksaBottomBar` (same `NavigationDestination` items):

```dart
final client = OryksaClient(getToken: myBackend.fetchOryksaToken); // returns "oryk_cs_..."

bottomNavigationBar: OryksaBottomBar(
  client: client,
  selectedIndex: tab,
  onDestinationSelected: (i) => setState(() => tab = i),
  destinations: const [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
    NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
    NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
  ],
),
```

Already have your own bar? Put `OryksaTabBubble` in the middle of it:

```dart
// in the Row of your bar
Row(children: [...leftTabs, OryksaTabBubble(client: client, showLabel: true, borderColor: barColor), ...rightTabs]);

// or docked in a BottomAppBar
floatingActionButton: OryksaTabBubble(client: client),
floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
```

* `lang`: `en`, `pt`, `br` or `es` (or a locale tag such as `pt-BR`). Leave it null to follow the language of the app (add `flutter_localizations` and your `supportedLocales`, as in the example).
* `theme`: null follows the light or dark theme of the app (`OryksaChatTheme()` / `OryksaChatTheme.dark()`); pass one to use your colors.
* `unread: true` shows a dot on the bubble (for example after a push from your server on the `message.replied` webhook); clear it in `onBubbleOpen` / `onOpen`.
* `appContext`: the screen the customer is on, sent with each message (see below).
* Screen readers hear "Talk to Sofia" ("Falar com Sofia", "Hablar con Sofia", plus "new message" when there is one). Right-to-left apps get the side panel on the left.
* Open the same chat from anywhere with `showOryksaChatScreen(context, client: client)`.

## Voice and app context (1.1)

The chat shows a microphone when your plan has voice. It opens the voice screen with the same behaviour as the ORYKSA app: the microphone stays open while she speaks and only a human voice cuts her off (typing, TV and her own echo do not); she stops on the word and the text stays in the chat; a whisper gets a whispered answer; if her voice fails, the text is shown (never a robot voice).

Microphone permission: Android `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`, iOS `NSMicrophoneUsageDescription` in Info.plist.

```dart
OryksaChatButton(
  client: client,
  lang: 'pt',
  // the screen the customer is on, so the AI answers about it
  appContext: () => const OryksaAppContext(screen: 'product', title: 'Sky Beginner Snowboard, 489.95'),
)
```

## How it works (and why the key stays safe)

1. Your **server** keeps the secret API key (`oryk_live_...`, created at developer.oryksa.com) and creates a short-lived **session token** for each signed-in user with `POST /v1/sessions`.
2. Your **app** receives only that session token (`oryk_cs_...`) and talks to ORYKSA with it. The secret key never goes into the app.
3. Every AI reply counts as one interaction of your ORYKSA plan, the same as on WhatsApp.

## In the app

```dart
import 'package:oryksa/oryksa.dart';

final client = OryksaClient(
  getToken: () async => await myBackend.fetchOryksaToken(), // returns "oryk_cs_..."
);

Scaffold(
  body: MyScreen(),
  floatingActionButton: OryksaChatButton(client: client, lang: 'en'), // en, pt, br, es
);
```

Open it from your own button with `showOryksaChat(context, client: client)`, or place the panel anywhere with `OryksaChat(client: client)`. Change colors with `OryksaChatTheme`.

Without the UI:

```dart
final agent = await client.agent();            // name, photo, greeting, suggestions
final text = await client.sendAndWait('Are you open on Saturday?');
final history = await client.messages();
```

## On your Dart server (secret key)

Server helpers are a separate library, **only for your backend**: never import it in the app. The app library (`package:oryksa/oryksa.dart`) serves your customers only and cannot change the AI or its Brain.

```dart
import 'package:oryksa/oryksa_server.dart';

final oryksa = Oryksa(Platform.environment['ORYKSA_API_KEY']!);

// session token for one user (send only client_token to the app)
final s = await oryksa.createSession(conversationId: 'user-42', customerName: 'Ana');

// keep the AI in sync with your app (call it on every release)
await oryksa.learnApp(
  name: 'FitTrack',
  description: 'Fitness app to log workouts and follow training plans.',
  screens: [{'title': 'Workouts', 'content': 'Tap + to log a workout.'}],
  faq: [{'question': 'How do I cancel Premium?', 'answer': 'Settings > Subscription > Cancel.'}],
);
```

Servers in other languages can call the same API: see https://developer.oryksa.com.

## Webhooks

```dart
import 'package:oryksa/oryksa_server.dart';

final event = verifyWebhook(rawBody, request.headers['oryksa-signature'], webhookSecret);
```

## Errors

Every failed call throws `OryksaException` with `status`, `code` (for example `interaction_limit_reached`, `rate_limited`, `plan_required`) and `message`.

---

## About the author

**Weslley Harakawa** - Founder of ORYKSA AI. Based in Lisbon, Portugal. Specialties: artificial intelligence, web and mobile development, blockchain tokenization. Education: University of the People.

- LinkedIn: https://www.linkedin.com/in/weslleyharakawa/
- ORYKSA AI Employees: https://oryksa.com (X: https://x.com/oryksa, Instagram: https://www.instagram.com/oryksaai, YouTube: https://www.youtube.com/@ORYKSAAI)

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda
