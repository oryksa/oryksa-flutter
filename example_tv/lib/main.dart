import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:oryksa/tv.dart';

import 'strings.dart';

/// ORYKSA TV SDK demo, a TEST app for Android TV, Google TV and Fire TV.
///
/// Without a chat token it runs on the SIMULATED backend: nothing it shows proves the
/// ORYKSA server. With one it uses the real server (a public session, no secret key):
///
///   flutter run --dart-define=ORYKSA_CHAT_TOKEN=... --dart-define=ORYKSA_TV_PLATFORM=fire_tv
const String _chatToken = String.fromEnvironment('ORYKSA_CHAT_TOKEN');
const String _platform = String.fromEnvironment('ORYKSA_TV_PLATFORM', defaultValue: 'fire_tv');

void main() => runApp(const DemoApp());

/// Writes to the log (logcat) what the server answered for each presenter line and each
/// call, for the proof. Never the token.
class _LoggingBackend implements OryksaTvBackend {
  _LoggingBackend(this.inner, this.onSpeech);

  final OryksaTvBackend inner;
  final void Function(String requested, OryksaTvSpeech? s) onSpeech;

  void _log(String m) => debugPrint('ORYKSA_TV_DEMO $m');

  @override
  String get platform => inner.platform;

  @override
  Future<OryksaTvConfig> config(String locale) async {
    final c = await inner.config(locale);
    _log('config requested=$locale locale=${c.locale} from_server=${c.fromServer} voice_rev=${c.voiceRev}');
    return c;
  }

  @override
  Future<OryksaTvSpeech?> speak(String text, {required String locale, bool whisper = false, bool voice = true, String? cachedRev}) async {
    try {
      final s = await inner.speak(text, locale: locale, whisper: whisper, voice: voice, cachedRev: cachedRev);
      _log(s == null
          ? 'speak requested=$locale result=no_voice'
          : 'speak requested=$locale voice=$voice cached_rev=${cachedRev ?? '-'} server_locale=${s.locale} voice_rev=${s.voiceRev} '
              'interactions_spent=${s.interactionsSpent} mp3_bytes=${s.bytes.length} chars=${text.length}');
      onSpeech(locale, s);
      return s;
    } catch (e) {
      _log('speak requested=$locale error=$e');
      rethrow;
    }
  }

  @override
  Future<OryksaReply> chat(String message, {required String locale, OryksaAppContext? appContext, bool voice = false}) async {
    final r = await inner.chat(message, locale: locale, appContext: appContext, voice: voice);
    _log('chat locale=$locale status=${r.status} reply_chars=${r.reply?.length ?? 0} speech_chars=${r.speech?.length ?? 0}');
    return r;
  }

  @override
  Future<OryksaAiResult> ai({String? instructions, String? input, Map<String, dynamic>? schema}) =>
      inner.ai(instructions: instructions, input: input, schema: schema);

  @override
  Future<OryksaPairing> pair(String locale) async {
    try {
      final p = await inner.pair(locale);
      // The code is on the TV screen anyway; it is short-lived and serves once.
      _log('pair ok code=${p.code} expires_in=${p.expiresIn.inSeconds}s');
      return p;
    } catch (e) {
      _log('pair error=$e');
      rethrow;
    }
  }

  @override
  Future<OryksaPhoneEventsPage> phoneEvents(String pairId, {int after = 0, Duration wait = const Duration(seconds: 25)}) async {
    try {
      final page = await inner.phoneEvents(pairId, after: after, wait: wait);
      for (final e in page.events) {
        _log('phone event seq=${e.seq} type=${e.type.name}'
            '${e.type == OryksaPhoneEventType.text ? ' lang=${e.lang} final=${e.isFinal} text="${e.text}"' : ''}');
      }
      return page;
    } catch (e) {
      _log('phone events error=$e');
      rethrow;
    }
  }

  @override
  Future<void> unpair(String pairId) => inner.unpair(pairId);
}

/// The demo app.
class DemoApp extends StatelessWidget {
  /// Creates the app.
  const DemoApp({super.key, this.tv});

  /// TV pieces to use (tests pass their own).
  final OryksaTv? tv;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ORYKSA TV Demo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF0E0B1A)),
        home: DemoHome(tv: tv),
      );
}

/// The demo screen.
class DemoHome extends StatefulWidget {
  /// Creates the screen.
  const DemoHome({super.key, this.tv});

  /// TV pieces to use (tests pass their own).
  final OryksaTv? tv;

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  late final OryksaTv tv;
  late final bool simulated;
  late String _locale;
  bool? _mic;
  String _lastPhone = '';
  StreamSubscription<String>? _phone;

  @override
  void initState() {
    super.initState();
    // The first language is the device's when it is one of the 8, otherwise English of the USA.
    _locale = demoInitialLocale(oryksaTvLocaleTag(WidgetsBinding.instance.platformDispatcher.locale));
    simulated = widget.tv == null ? _chatToken.isEmpty : widget.tv!.backend is OryksaTvFakeBackend;
    tv = widget.tv ??
        OryksaTv.withBackend(
          _LoggingBackend(
            _chatToken.isEmpty
                ? OryksaTvFakeBackend(platform: _platform)
                : OryksaTvClientBackend(OryksaClient.public(
                    chatToken: _chatToken,
                    conversationId: 'tvdemo${Random().nextInt(1 << 32)}',
                    platform: _platform,
                    appId: 'com.oryksa.oryksa_tv_demo',
                  )),
            (requested, s) {},
          ),
          locale: _locale,
        );
    if (widget.tv != null) tv.locale = _locale;
    // Technical labels (mode, platform, locale codes, voices) go to the log only, never on screen.
    debugPrint('ORYKSA_TV_DEMO start mode=${simulated ? 'SIMULATED' : 'REAL'} platform=$_platform locale=$_locale');
    tv.presenter.onError = (e) => debugPrint('ORYKSA_TV_DEMO presenter error: $e');
    tv.addListener(_changed);
    tv.configOrFallback();
    _phone = tv.phoneVoice.texts.listen((t) => setState(() => _lastPhone = t));
    OryksaTvMic.isAvailable().then((ok) {
      if (mounted) setState(() => _mic = ok);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _phone?.cancel();
    tv.removeListener(_changed);
    tv.dispose();
    super.dispose();
  }

  /// Changes everything at once: the screen, the server's texts and the voice.
  void _nextLocale() {
    final i = (demoLocales.indexOf(_locale) + 1) % demoLocales.length;
    setState(() => _locale = demoLocales[i]);
    tv.locale = _locale;
    tv.configOrFallback();
    debugPrint('ORYKSA_TV_DEMO locale=$_locale');
  }

  Future<void> _pairPhone() => showDialog<void>(
        context: context,
        // What a screen reader says for the area around the card: the server's "close", in this language.
        barrierLabel: (tv.currentConfig?.texts ?? const OryksaTvTexts({})).get('close'),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: OryksaPairingCard(tv: tv),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = OryksaTvMetrics.of(context);
    final s = demoStrings(_locale);
    final style = TextStyle(fontSize: m.text, color: Colors.white70);
    // The phone button: the label the server gives (tv.actions phone_voice), else the demo's own.
    final cfg = tv.currentConfig;
    final phoneAction = cfg?.actions.where((a) => a.kind == OryksaTvActionKind.phoneVoice).firstOrNull;
    final phoneLabel = (cfg != null && cfg.locale == OryksaTvFakeBackend.resolveLocale(_locale) && phoneAction != null)
        ? phoneAction.label
        : s['phone']!;
    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: m.safe,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['title']!, key: const ValueKey('demo-title'), style: TextStyle(fontSize: m.title, fontWeight: FontWeight.w800)),
                if (simulated) ...[
                  SizedBox(height: m.px(12)),
                  Container(
                    key: const ValueKey('demo-mode'),
                    padding: EdgeInsets.symmetric(horizontal: m.px(20), vertical: m.px(8)),
                    color: const Color(0xFFB45309),
                    child: Text(s['simulated']!, style: TextStyle(fontSize: m.small, fontWeight: FontWeight.w700)),
                  ),
                ],
                SizedBox(height: m.px(20)),
                Text('${s['language']}: ${s['language_name']}', key: const ValueKey('demo-locale'), style: style),
                if (_mic != null) Text('${s['mic']}: ${_mic! ? s['mic_yes'] : s['mic_no']}', style: style),
                if (_lastPhone.isNotEmpty) Text('${s['phone_last']}: “$_lastPhone”', style: style),
                SizedBox(height: m.px(40)),
                FocusTraversalGroup(
                  child: Wrap(
                    spacing: m.px(24),
                    runSpacing: m.px(24),
                    children: [
                      OryksaTvButton(
                        label: s['presenter']!,
                        icon: Icons.record_voice_over_rounded,
                        autofocus: true,
                        onPressed: () => tv.presenter.say(s['welcome']!),
                      ),
                      OryksaTvButton(
                        label: s['assistant']!,
                        icon: Icons.chat_rounded,
                        onPressed: () => showOryksaTvAssistant(context, tv: tv),
                      ),
                      OryksaTvButton(label: phoneLabel, icon: Icons.qr_code_rounded, onPressed: _pairPhone),
                      OryksaTvButton(label: s['change_language']!, icon: Icons.translate_rounded, onPressed: _nextLocale),
                    ],
                  ),
                ),
              ],
            ),
          ),
          OryksaPresenterView(tv: tv),
        ],
      ),
    );
  }
}