<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# oryksa

[![English](https://img.shields.io/badge/English-30363d?style=for-the-badge)](README.md) [![Português](https://img.shields.io/badge/Portugu%C3%AAs-30363d?style=for-the-badge)](README.pt.md) [![Español](https://img.shields.io/badge/Espa%C3%B1ol-0891b2?style=for-the-badge)](README.es.md) [![Français](https://img.shields.io/badge/Fran%C3%A7ais-30363d?style=for-the-badge)](README.fr.md)

SDK oficial de Flutter de **ORYKSA AI Employees**. Pon dentro de tu app Flutter (Android, iOS, web y escritorio) un empleado de IA que ya conoce tu negocio: una burbuja redonda con la foto de tu IA en el centro de tu barra de pestañas, un chat listo con el mismo aspecto que el chat de la web de ORYKSA, el nombre y la foto de tu IA desde tu cuenta ORYKSA, en inglés, portugués y español.

* Documentación: https://developer.oryksa.com/es/sdks
* API: `https://api.oryksa.com/v1`

## Instalar

```bash
flutter pub add oryksa
```

## Para qué sirve

El SDK pone el chat y la voz de ORYKSA dentro de tu app para atender a los **clientes de tu negocio**: preguntan, compran y reservan. La IA responde con tu Brain, tus productos y tus servicios, con el nombre, la foto y la voz que elegiste en *Tu IA*, y guarda leads, reservas y ventas en las Actividades de tu cuenta ORYKSA. **No** es una interfaz para el dueño: a través del SDK nadie cambia ajustes, lee las Actividades ni da órdenes a ORYKSA. Más información: https://help.oryksa.com/es/a/sdks-what-they-do

Las palabrotas que escribe el cliente aparecen con asteriscos en el chat (la misma lista de todos los chats de ORYKSA, cargada desde `https://app.oryksa.com/widget/profanity.json` y guardada 24 horas). Las respuestas de la IA ya vienen filtradas desde el servidor.

## Burbuja en la barra de pestañas (1.2)

La burbuja redonda con la foto de tu IA en el centro de la barra de pestañas inferior, igual que en la app de ORYKSA. Al tocarla se abre el chat (con el micrófono para la voz): pantalla completa en el móvil, panel lateral en pantallas anchas (840 dp o más: tablets, plegables abiertos, escritorio), para que tu app siga visible al lado. El nombre y la foto vienen de *Tu IA* en tu cuenta ORYKSA.

<p align="center"><img src="https://developer.oryksa.com/assets/img/sdk/flutter-tab-bubble.png" width="760" alt="Burbuja de ORYKSA en la barra de pestañas: la barra, el chat, la pantalla de voz y el panel lateral en una tablet"></p>

Cambia tu `NavigationBar` por `OryksaBottomBar` (los mismos elementos `NavigationDestination`):

```dart
final client = OryksaClient(getToken: myBackend.fetchOryksaToken); // devuelve "oryk_cs_..."

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

¿Ya tienes tu propia barra? Pon `OryksaTabBubble` en el centro:

```dart
// en la Row de tu barra
Row(children: [...leftTabs, OryksaTabBubble(client: client, showLabel: true, borderColor: barColor), ...rightTabs]);

// o acoplada en una BottomAppBar
floatingActionButton: OryksaTabBubble(client: client),
floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
```

* `lang`: `en`, `pt`, `br` o `es` (o una etiqueta de configuración regional como `pt-BR`). Déjalo en null para seguir el idioma de la app (añade `flutter_localizations` y tus `supportedLocales`, como en el ejemplo).
* `theme`: null sigue el tema claro u oscuro de la app (`OryksaChatTheme()` / `OryksaChatTheme.dark()`); pasa uno para usar tus colores.
* `unread: true` muestra un punto en la burbuja (por ejemplo, después de un push de tu servidor con el webhook `message.replied`); quítalo en `onBubbleOpen` / `onOpen`.
* `appContext`: la pantalla en la que está el cliente, enviada con cada mensaje (ver más abajo).
* Los lectores de pantalla oyen "Talk to Sofia" ("Falar com Sofia", "Hablar con Sofia", más "new message" cuando hay un mensaje nuevo). En las apps de derecha a izquierda, el panel lateral aparece a la izquierda.
* Abre el mismo chat desde cualquier lugar con `showOryksaChatScreen(context, client: client)`.

**Foto de la IA o logo de la empresa (1.2.1).** Por defecto, la burbuja muestra la foto de tu IA. Para mostrar en su lugar el logo de tu empresa, elige "Logo de la empresa" en el panel de ORYKSA (Conectores > Chat del sitio): la burbuja muestra el logo entero sobre fondo blanco, con el nombre de tu negocio debajo. El chat que se abre mantiene la foto y el nombre de tu IA. Tu app también puede forzar una imagen con `image:` en `OryksaTabBubble` (o `bubbleImage:` en `OryksaBottomBar`), por ejemplo `bubbleImage: const AssetImage('assets/logo.png')`.

## Voz y contexto de la app (1.1)

El chat muestra un micrófono cuando tu plan incluye voz. Abre la pantalla de voz con el mismo comportamiento que la app de ORYKSA: el micrófono sigue abierto mientras ella habla y solo una voz humana la interrumpe (el tecleo, la televisión y su propio eco no); se detiene en la palabra y el texto queda en el chat; a un susurro responde con un susurro; si su voz falla, se muestra el texto (nunca una voz robótica).

Permiso de micrófono: Android `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`, iOS `NSMicrophoneUsageDescription` en Info.plist.

```dart
OryksaChatButton(
  client: client,
  lang: 'pt',
  // la pantalla en la que está el cliente, para que la IA responda sobre ella
  appContext: () => const OryksaAppContext(screen: 'product', title: 'Sky Beginner Snowboard, 489.95'),
)
```

## Cómo funciona (y por qué la clave está segura)

1. Tu **servidor** guarda la clave secreta de la API (`oryk_live_...`, creada en developer.oryksa.com) y crea un **token de sesión** de corta duración para cada usuario que ha iniciado sesión, con `POST /v1/sessions`.
2. Tu **app** recibe solo ese token de sesión (`oryk_cs_...`) y habla con ORYKSA con él. La clave secreta nunca entra en la app.
3. Cada respuesta de la IA cuenta como una interacción de tu plan ORYKSA, igual que en WhatsApp.

## En la app

```dart
import 'package:oryksa/oryksa.dart';

final client = OryksaClient(
  getToken: () async => await myBackend.fetchOryksaToken(), // devuelve "oryk_cs_..."
);

Scaffold(
  body: MyScreen(),
  floatingActionButton: OryksaChatButton(client: client, lang: 'en'), // en, pt, br, es
);
```

Ábrelo desde tu propio botón con `showOryksaChat(context, client: client)`, o coloca el panel en cualquier lugar con `OryksaChat(client: client)`. Cambia los colores con `OryksaChatTheme`.

Sin la interfaz:

```dart
final agent = await client.agent();            // nombre, foto, saludo, sugerencias
final text = await client.sendAndWait('Are you open on Saturday?');
final history = await client.messages();
```

## En tu servidor Dart (clave secreta)

Las funciones de servidor están en una biblioteca aparte, **solo para tu backend**: nunca la importes en la app. La biblioteca de la app (`package:oryksa/oryksa.dart`) atiende solo a tus clientes y no puede cambiar la IA ni su Brain.

```dart
import 'package:oryksa/oryksa_server.dart';

final oryksa = Oryksa(Platform.environment['ORYKSA_API_KEY']!);

// token de sesión para un usuario (envía a la app solo client_token)
final s = await oryksa.createSession(conversationId: 'user-42', customerName: 'Ana');

// mantén la IA sincronizada con tu app (llámalo en cada versión)
await oryksa.learnApp(
  name: 'FitTrack',
  description: 'Fitness app to log workouts and follow training plans.',
  screens: [{'title': 'Workouts', 'content': 'Tap + to log a workout.'}],
  faq: [{'question': 'How do I cancel Premium?', 'answer': 'Settings > Subscription > Cancel.'}],
);
```

Los servidores en otros lenguajes pueden llamar a la misma API: consulta https://developer.oryksa.com.

## Webhooks

```dart
import 'package:oryksa/oryksa_server.dart';

final event = verifyWebhook(rawBody, request.headers['oryksa-signature'], webhookSecret);
```

## Errores

Toda llamada que falla lanza `OryksaException` con `status`, `code` (por ejemplo `interaction_limit_reached`, `rate_limited`, `plan_required`) y `message`.

---

## Sobre el autor

**Weslley Harakawa** - Fundador de ORYKSA AI. En Lisboa, Portugal. Especialidades: inteligencia artificial, desarrollo web y móvil, tokenización en blockchain. Formación: University of the People.

- LinkedIn: https://www.linkedin.com/in/weslleyharakawa/
- ORYKSA AI Employees: https://oryksa.com (X: https://x.com/oryksa, Instagram: https://www.instagram.com/oryksaai, YouTube: https://www.youtube.com/@ORYKSA)

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda
