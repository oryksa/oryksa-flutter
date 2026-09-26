<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# oryksa

Official Flutter SDK for **ORYKSA AI Employees**. Put an AI employee that already knows your business inside your Flutter app (Android, iOS, web and desktop): a ready chat with the same look as the ORYKSA website chat, the name and photo of your AI from your ORYKSA account, in English, Portuguese (Portugal and Brazil) and Spanish.

* Docs: https://developer.oryksa.com/en/sdks
* API: `https://api.oryksa.com/v1`

## Install

```bash
flutter pub add oryksa
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

```dart
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
final event = verifyWebhook(rawBody, request.headers['oryksa-signature'], webhookSecret);
```

## Errors

Every failed call throws `OryksaException` with `status`, `code` (for example `interaction_limit_reached`, `rate_limited`, `plan_required`) and `message`.

---

## Português (Portugal)

SDK oficial Flutter da **ORYKSA AI Employees**: põe na tua app um colaborador de IA que já conhece o teu negócio, com um chat pronto igual ao chat do site da ORYKSA, com o nome e a foto da tua IA.

1. O teu **servidor** guarda a chave secreta e cria um token de sessão para cada utilizador (`POST /v1/sessions`).
2. A **app** usa só esse token: `OryksaClient(getToken: ...)` e `OryksaChatButton(client: client, lang: 'pt')`.
3. Cada resposta da IA conta como uma interação do teu plano.

## Português (Brasil)

SDK oficial Flutter da **ORYKSA AI Employees**: coloque no seu app um colaborador de IA que já conhece o seu negócio, com um chat pronto igual ao chat do site da ORYKSA, com o nome e a foto da sua IA.

1. Seu **servidor** guarda a chave secreta e cria um token de sessão para cada usuário (`POST /v1/sessions`).
2. O **app** usa só esse token: `OryksaClient(getToken: ...)` e `OryksaChatButton(client: client, lang: 'br')`.
3. Cada resposta da IA conta como uma interação do seu plano.

## Español

SDK oficial de Flutter de **ORYKSA AI Employees**: pon en tu app un empleado de IA que ya conoce tu negocio, con un chat listo igual al chat de la web de ORYKSA, con el nombre y la foto de tu IA.

1. Tu **servidor** guarda la clave secreta y crea un token de sesión para cada usuario (`POST /v1/sessions`).
2. La **app** usa solo ese token: `OryksaClient(getToken: ...)` y `OryksaChatButton(client: client, lang: 'es')`.
3. Cada respuesta de la IA cuenta como una interacción de tu plan.

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda
