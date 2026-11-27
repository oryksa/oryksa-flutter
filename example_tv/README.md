# ORYKSA TV SDK demo

A test app for `package:oryksa/tv.dart` on Android TV, Google TV and Fire TV (Fire OS):
the presenter, the assistant panel driven by the remote, and the phone voice by QR.

**Simulated by default.** Without a chat token the app runs on `OryksaTvFakeBackend`
and shows the orange band "SIMULADO": nothing it shows proves the ORYKSA server.

With the public chat token of an ORYKSA account (ORYKSA > Connectors > Website chat) it
uses the real server, through a public session (never a secret key):

```
flutter build apk --release --dart-define=ORYKSA_CHAT_TOKEN=<token> --dart-define=ORYKSA_TV_PLATFORM=fire_tv
```

The manifest declares the microphone, the touchscreen and leanback as not required, so
the stores do not hide the app on TVs without them, and adds the TV launcher
(`LEANBACK_LAUNCHER`) with a banner.

Author: ORYKSA AI Employees (https://oryksa.com)
