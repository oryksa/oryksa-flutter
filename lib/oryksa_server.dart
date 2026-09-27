/// ORYKSA server helpers: ONLY for the subscriber's own backend (Dart servers such as
/// shelf, dart_frog or serverpod). Never import this library in a Flutter app.
///
/// * [Oryksa]: server client with the SECRET API key (`oryk_live_...`): session tokens
///   for the app ([Oryksa.createSession]) and the calls that change the AI and its Brain
///   ([Oryksa.updateAgent], [Oryksa.setPages], [Oryksa.addFaq], [Oryksa.learnApp]).
/// * [verifyWebhook]: checks the signature of ORYKSA webhooks.
///
/// The app library (`package:oryksa/oryksa.dart`) serves the customers of the business
/// only and does not include any of this.
///
/// Docs: https://developer.oryksa.com
library;

export 'src/errors.dart';
export 'src/models.dart';
export 'src/server.dart';
export 'src/webhook.dart';
