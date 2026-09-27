/// Official Flutter SDK for ORYKSA AI Employees.
///
/// * [OryksaClient]: in-app client. Uses a short-lived session token created by
///   your server, never the secret API key.
/// * [OryksaChat] and [OryksaChatButton]: a ready chat with the name and photo of
///   the AI from the ORYKSA account, with voice ([OryksaVoiceScreen]): the same
///   behaviour as the ORYKSA app (only a human voice cuts her off).
/// * [Vad]: the ORYKSA voice engine (decides when someone speaks, stops, or cuts in).
/// * [Oryksa]: server client for Dart backends (secret API key).
/// * [verifyWebhook]: checks the signature of ORYKSA webhooks.
///
/// Docs: https://developer.oryksa.com
library;

export 'src/errors.dart';
export 'src/models.dart';
export 'src/client.dart';
export 'src/server.dart';
export 'src/webhook.dart';
export 'src/chat.dart';
export 'src/voice.dart';
export 'src/voice_screen.dart';
export 'vad.dart';
