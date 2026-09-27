/// Official Flutter SDK for ORYKSA AI Employees.
///
/// * [OryksaClient]: in-app client. Uses a short-lived session token created by
///   your server, never the secret API key.
/// * [OryksaChat] and [OryksaChatButton]: a ready chat with the name and photo of
///   the AI from the ORYKSA account, with voice ([OryksaVoiceScreen]): the same
///   behaviour as the ORYKSA app (only a human voice cuts her off).
/// * [Vad]: the ORYKSA voice engine (decides when someone speaks, stops, or cuts in).
///
/// This library serves the customers of the business only. The server helpers (secret
/// API key, changes to the AI and its Brain, webhooks) live in
/// `package:oryksa/oryksa_server.dart`, for the subscriber's backend only.
///
/// Docs: https://developer.oryksa.com
library;

export 'src/errors.dart';
export 'src/models.dart';
export 'src/client.dart';
export 'src/chat.dart';
export 'src/profanity.dart';
export 'src/voice.dart';
export 'src/voice_screen.dart';
export 'vad.dart';
