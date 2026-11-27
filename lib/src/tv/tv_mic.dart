import 'package:record/record.dart';

/// The TV's own microphone.
class OryksaTvMic {
  OryksaTvMic._();

  /// True when the device lists at least one audio input for apps (on Android,
  /// `AudioManager.getDevices(GET_DEVICES_INPUTS)`). It never asks for the permission:
  /// on the Fire TV Stick the system denies it by itself, so the SDK only asks when there
  /// is a microphone to open. False when it cannot tell.
  ///
  /// A listed input is not yet proof of sound: some TVs list an input that only gives
  /// silence. Check what you hear before you rely on it.
  static Future<bool> isAvailable() async {
    AudioRecorder? r;
    try {
      r = AudioRecorder();
      return (await r.listInputDevices()).isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      try {
        await r?.dispose();
      } catch (_) {}
    }
  }
}
