/// ORYKSA for TV apps (Android TV, Google TV, Fire TV with Fire OS).
///
/// * [OryksaTv]: the TV pieces of your app, on an [OryksaClient] (create it with the TV
///   `platform`, for example `OryksaTvPlatform.fireTv.wire`).
/// * [OryksaPresenter] and [OryksaPresenterView]: the AI speaks on screen with the voice of
///   the locale (from the server) and big subtitles.
/// * [OryksaTvAssistant] and [showOryksaTvAssistant]: a conversation with the AI driven only
///   by the remote (arrows, OK, Back).
/// * [OryksaPhoneVoice] and [OryksaPairingCard]: the phone as the microphone, by QR, for
///   TVs that give no microphone to apps.
/// * [OryksaTvMic]: whether the TV has a microphone for apps.
/// * `client.ai` (from `package:oryksa/oryksa.dart`): any AI task of your app, for example
///   moderating or classifying.
///
/// [OryksaTvFakeBackend] is a SIMULATED backend for tests and demos: nothing shown with it
/// proves the real server.
///
/// Docs: https://developer.oryksa.com
library;

export 'oryksa.dart';
export 'src/tv/tv_assistant.dart' show OryksaTvAssistant, showOryksaTvAssistant;
export 'src/tv/tv_audio.dart' show OryksaTvAudioPlayer, OryksaTvJustAudioPlayer;
export 'src/tv/tv_backend.dart';
export 'src/tv/tv_core.dart';
export 'src/tv/tv_fake_backend.dart';
export 'src/tv/tv_mic.dart';
export 'src/tv/tv_models.dart';
export 'src/tv/tv_phone_voice.dart';
export 'src/tv/tv_text.dart';
export 'src/tv/tv_widgets.dart';
