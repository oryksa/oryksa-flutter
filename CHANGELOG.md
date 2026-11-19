## 1.2.3

* **The lead now says which app it came from.** Every message sent with `OryksaClient.send`
  (and so everything the chat and the voice screen send) carries `platform`: `ios` on an
  iPhone or iPad, `android` on an Android phone or tablet, `flutter` on the web, macOS,
  Windows and Linux. The owner's new-lead notice can then say "in your app (iPhone)" or
  "(Android)" instead of just "in your app". Before this, `platform` only went out when the
  message carried voice numbers, so a lead that was typed arrived with no device at all.
* `X-ORYKSA-SDK` now reports the real version. The constant had been left at 1.2.1 while
  pub.dev served 1.2.2, so every 1.2.2 install logged itself as 1.2.1. A test now fails if
  it ever drifts from `pubspec.yaml` again.
* Voice telemetry keeps working: the server reads `ios` and `android` as the `sdk_ios` and
  `sdk_android` channels, and `flutter` as before.

## 1.2.2

* **Android voice fixed.** On Android the voice screen got stuck on "I'm listening": the AI's spoken answer never played and the microphone stopped after her first reply. Two causes, both fixed:
  * Her voice now plays from a temporary file. Playing bytes from memory goes through a local `http://127.0.0.1` proxy, which Android 9+ blocks unless the app allows cleartext traffic. No change is needed in your app (web keeps playing from memory).
  * The microphone no longer pauses when her voice starts (`audioInterruption: none`; record_android 1.5+ paused it for good). If the microphone ever stops delivering sound, it reopens by itself.
* **Open in voice or chat.** The bubble opens what the business chose in the ORYKSA panel (Connectors > Website chat > Open in). The default is the voice screen. `OryksaAgent.openMode` (`voice` or `chat`), `showOryksaChatScreen(startInVoice:)` and `OryksaChat(startInVoice:)`. Closing the voice screen leaves the customer in the chat. With no voice in the plan the chat opens as before.
* **Type it in the voice screen.** When the AI asks for an e-mail, a phone number or a name, the voice screen shows a text box to type it (`OryksaReply.collecting`, `OryksaVoiceController.sendText`).
* **The halo breathes** while the conversation is open and grows with the customer's voice (`OryksaVoiceController.level`).
* **Faster and steadier turns:**
  * the closing silence is cut before the upload;
  * a pending reply is checked every 0.5 s (was 1.5 s);
  * a cough or the TV while she is thinking no longer throws away the answer on its way;
  * noise transcribed as "." is not sent as a message.
* Needs `record` 6.2 or newer.

## 1.2.1

* **Company logo in the tab bar bubble.** The business now chooses in the ORYKSA panel (Connectors > Website chat) whether the bubble shows the photo of the AI or the company logo. With the logo, the bubble shows the whole logo on white (not cropped) and the business name under it. The chat and the voice screen that open on tap keep the photo and name of the AI, and screen readers still hear "Talk to" + the name of the AI.
* `OryksaTabBubble(image:)` and `OryksaBottomBar(bubbleImage:)`: an image of your app (for example `AssetImage('assets/logo.png')`) for the bubble, over what the panel chose. `label` / `bubbleLabel` still win over the text from the panel.
* `OryksaAgent` gets `launcherIcon` (`ai` or `logo`), `launcherImage` and `launcherLabel`, read from `launcher` in `GET /v1/client/agent`. With an older server that does not send it, the bubble shows the photo and name of the AI, as in 1.2.0.

## 1.2.0

* **Tab bar bubble.** `OryksaTabBubble`: the round button with the photo of the AI (from *Your AI* in ORYKSA), a ring and an optional unread dot, for the middle of a bottom tab bar, as in the ORYKSA app. Tapping it opens the chat with voice.
* `OryksaBottomBar`: a Material 3 style bottom bar with your `NavigationDestination` items and the bubble in the middle (same `selectedIndex` / `onDestinationSelected` as `NavigationBar`). The bubble rises a little above the bar (`raise`), the bar follows the app theme and the safe area.
* `showOryksaChatScreen`: the chat full screen on phones and as a side panel on wide screens (840 dp or more), at the end of the screen (the left in right-to-left apps), so the app stays visible beside it.
* The microphone in the chat opens the voice screen, with the same behaviour as before.
* Dark mode: `OryksaChatTheme.dark()` and `OryksaChatTheme.of(context)`; the bubble and its chat follow the light or dark theme of the app when no theme is given. New `line` color in `OryksaChatTheme`.
* Languages: `lang` also accepts locale tags (`pt-BR`, `pt_BR`, `pt-PT`, `es-ES`); the bubble and the bar follow the app locale when `lang` is null (`oryksaLang`, `oryksaLangOf`). Accessibility label "Talk to" + the name of the AI in English, Portuguese (Portugal and Brazil) and Spanish, with "new message" when the dot is on.
* The chat sends the language of the screen with each message (`lang` in `send`, `sendAndWait`, `sendAndWaitReply` and `OryksaVoiceController`), so a short message such as "ok" gets the reply in that language.
* Right-to-left safe chat bubbles and paddings.
* Example app: four tabs with the bubble in the middle, the language of the phone, light and dark, two columns on tablets.
* Server side: `createSession` takes `customerEmail` and `customerPhone`. For a user signed in to your app, the AI asks for no contact details and never tells them to register or sign in.
* Apps without a server of their own: `OryksaClient.public(chatToken: ...)` opens the chat with the business's public chat token (the one the website chat uses); no secret key, and the conversation is kept apart from the ones a server creates.
* Photos: `OryksaImage` and `send(..., image:)`; `onPickImage` on the chat, the bubble and the bar shows a camera button (bring your own picker, for example `image_picker`). The AI looks at the photo and answers about it.
* Needs Flutter 3.27 or newer (the SDK already used APIs from it).

## 1.1.1

- Voice screen: the words the person says are never shown on screen. While the AI thinks it shows "I'm listening" / "One moment..." in the interface language; the AI's answer still shows as text. Same behaviour as the ORYKSA apps, web and extensions.

## 1.1.0

* Copy button under each reply of the AI (copies the text, shows a check for a moment), as in the ORYKSA apps and extension.
* Voice: a voice screen with the photo of the AI ("I'm listening" / her answer, Mute, Close) opened from the microphone in the chat. The same behaviour as the ORYKSA app: the microphone stays open while she speaks and only a human voice cuts her off (typing, TV, birds and her own echo do not); she stops on the word and the text stays in the chat; the second before the cut is kept; 700 ms of silence closes a sentence (15 s at most); a whisper gets a whispered, shorter answer; her voice is the one chosen in ORYKSA and, if it fails, the text is shown without a robot voice.
* The voice engine is the ORYKSA app engine (`Vad`), with the same audio tests on real recordings.
* `appContext`: tell the AI which screen of your app the customer is on (product, cart, booking) so it answers about it.
* The client gets `tts`, `transcribe` and `voiceStats`; `send` accepts `voice`, `whisper`, `appContext` and returns `speech` (the short spoken version).
* The agent includes `photo` (the AI photo from Your AI), `voice` and `language`.
* Bold text (`**`) in the chat bubbles.
* The SDK serves the customers of the business only: it is never an interface for the owner.
* **Breaking:** the server helpers moved out of the app library. `Oryksa` (secret API key: `createSession`, `updateAgent`, `setPages`, `addFaq`, `learnApp`) and `verifyWebhook` are now in `package:oryksa/oryksa_server.dart`, only for the subscriber's backend. A Flutter app that imports `package:oryksa/oryksa.dart` can no longer change the AI or its Brain.
* Needs the microphone permission for voice: Android `RECORD_AUDIO`, iOS `NSMicrophoneUsageDescription`.

## 1.0.1

* README: about the author.

## 1.0.0

* First release.
* `OryksaClient`: in-app client with short-lived session tokens (agent, send, sendAndWait, messages).
* `OryksaChat`, `OryksaChatButton` and `showOryksaChat`: ready chat with the look of the ORYKSA website chat, name and photo of the AI from the ORYKSA account, in English, Portuguese (Portugal and Brazil) and Spanish.
* `Oryksa`: server client for Dart backends (chat, sessions, Brain pages and FAQ, learnApp).
* `verifyWebhook`: ORYKSA webhook signature check.
