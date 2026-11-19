// Which device the customer is on, sent as `platform` in every POST /v1/client/chat so the
// owner's new-lead e-mail can say "na tua app (iPhone)" or "(Android)". The server also
// uses it as the voice telemetry channel (sdk_ios / sdk_android).
export 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';
