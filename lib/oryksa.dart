/// Official Flutter SDK for ORYKSA AI Employees.
///
/// * [OryksaClient]: in-app client. Uses a short-lived session token created by
///   your server, never the secret API key.
/// * [OryksaChat] and [OryksaChatButton]: a ready chat with the same look as the
///   ORYKSA website chat (name and photo of the AI come from the ORYKSA account).
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
