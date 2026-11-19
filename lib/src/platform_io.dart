import 'dart:io';

/// `ios` or `android` on a phone or tablet; `flutter` on macOS, Windows and Linux,
/// where there is no app store lead to attribute. The server reads `ios` / `android`
/// (POST /v1/client/chat) and falls back to the User-Agent when this is anything else.
final String oryksaPlatform = Platform.isIOS
    ? 'ios'
    : Platform.isAndroid
        ? 'android'
        : 'flutter';
