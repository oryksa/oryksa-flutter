import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_core.dart';
import 'tv_models.dart';
import 'tv_phone_voice.dart';

/// Colours of the TV pieces. Pass your app's colours; the sizes and the focus ring stay big.
@immutable
class OryksaTvTheme {
  /// Creates a theme.
  const OryksaTvTheme({
    this.background = const Color(0xFF0E0B1A),
    this.surface = const Color(0xFF221C38),
    this.text = const Color(0xFFFFFFFF),
    this.muted = const Color(0xFFC4BFD8),
    this.accent = const Color(0xFF6E4BFF),
    this.focus = const Color(0xFFFFFFFF),
    this.subtitleBackground = const Color(0xD9000000),
  });

  /// Background of the panel.
  final Color background;

  /// Background of buttons and cards.
  final Color surface;

  /// Main text.
  final Color text;

  /// Secondary text.
  final Color muted;

  /// Focused button and highlights.
  final Color accent;

  /// Ring around the focused item.
  final Color focus;

  /// Box behind the subtitles.
  final Color subtitleBackground;
}

/// Sizes for a TV screen: given in pixels of a 1080p screen and scaled to the real one, so
/// they look the same on any TV whatever its density.
@immutable
class OryksaTvMetrics {
  /// Creates metrics.
  const OryksaTvMetrics(this.unit, this.size);

  /// Metrics of the screen of [context].
  factory OryksaTvMetrics.of(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    final h = math.min(s.height, s.width * 9 / 16);
    return OryksaTvMetrics(h <= 0 ? 0.5 : h / 1080, s);
  }

  /// Logical pixels per 1080p pixel.
  final double unit;

  /// Screen size.
  final Size size;

  /// [v] pixels of a 1080p screen in logical pixels.
  double px(double v) => v * unit;

  /// Body text (28 px at 1080p).
  double get text => px(28);

  /// Small text (24 px at 1080p).
  double get small => px(24);

  /// Titles (44 px at 1080p).
  double get title => px(44);

  /// Subtitles of the presenter (40 px at 1080p).
  double get subtitle => px(40);

  /// Width of the focus ring.
  double get focusWidth => px(5);

  /// 5 % margin on every side: TVs may cut the edges of the picture.
  EdgeInsets get safe => EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.05);
}

/// A button for the TV remote: OK presses it, the arrows move to it, and when it has the
/// focus it grows, fills with the accent colour and gets a thick ring.
class OryksaTvButton extends StatefulWidget {
  /// Creates a button.
  const OryksaTvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.theme = const OryksaTvTheme(),
  });

  /// Text on the button.
  final String label;

  /// Called with OK (or a tap).
  final VoidCallback onPressed;

  /// Optional icon before the text.
  final IconData? icon;

  /// Takes the focus when it appears.
  final bool autofocus;

  /// Optional focus node.
  final FocusNode? focusNode;

  /// Colours.
  final OryksaTvTheme theme;

  @override
  State<OryksaTvButton> createState() => _OryksaTvButtonState();
}

class _OryksaTvButtonState extends State<OryksaTvButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = OryksaTvMetrics.of(context);
    final th = widget.theme;
    void press() => widget.onPressed();
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        onFocusChange: (f) {
          setState(() => _focused = f);
          // In a scrolling row or list, bring the focused button into view.
          if (f) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 150));
        },
        mouseCursor: SystemMouseCursors.click,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            press();
            return null;
          }),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
            press();
            return null;
          }),
        },
        child: GestureDetector(
          onTap: press,
          child: AnimatedScale(
            scale: _focused ? 1.08 : 1,
            duration: const Duration(milliseconds: 120),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: EdgeInsets.symmetric(horizontal: m.px(32), vertical: m.px(16)),
              decoration: BoxDecoration(
                color: _focused ? th.accent : th.surface,
                borderRadius: BorderRadius.circular(m.px(16)),
                border: Border.all(color: _focused ? th.focus : Colors.transparent, width: m.focusWidth),
                boxShadow: _focused ? [BoxShadow(color: th.accent.withValues(alpha: 0.6), blurRadius: m.px(28))] : const [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: m.text * 1.1, color: th.text),
                    SizedBox(width: m.px(12)),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: m.text,
                        color: th.text,
                        fontWeight: _focused ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round photo of the AI, with a ring while she speaks.
class OryksaTvAvatar extends StatelessWidget {
  /// Creates the photo.
  const OryksaTvAvatar({super.key, required this.url, required this.size, this.speaking = false, this.theme = const OryksaTvTheme()});

  /// Photo address.
  final String url;

  /// Diameter.
  final double size;

  /// Shows the ring.
  final bool speaking;

  /// Colours.
  final OryksaTvTheme theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.05),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: speaking ? theme.accent : theme.surface,
        boxShadow: speaking ? [BoxShadow(color: theme.accent.withValues(alpha: 0.7), blurRadius: size * 0.3)] : const [],
      ),
      child: ClipOval(
        child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: theme.surface)),
      ),
    );
  }
}

/// The presenter on screen: her photo and name, and the subtitles in big letters. Place it
/// over your screen (for example at the bottom of a [Stack]). It hides itself when she is
/// quiet unless [showWhenIdle].
///
/// With [remoteSkips], while she speaks OK and Back on the remote stop her (and are not
/// passed to your app).
class OryksaPresenterView extends StatefulWidget {
  /// Creates the view of `tv.presenter`.
  const OryksaPresenterView({
    super.key,
    required this.tv,
    this.theme = const OryksaTvTheme(),
    this.remoteSkips = true,
    this.showWhenIdle = false,
  });

  /// The TV pieces.
  final OryksaTv tv;

  /// Colours.
  final OryksaTvTheme theme;

  /// OK and Back stop her while she speaks.
  final bool remoteSkips;

  /// Keeps the photo and name on screen when she is quiet.
  final bool showWhenIdle;

  @override
  State<OryksaPresenterView> createState() => _OryksaPresenterViewState();
}

/// The remote keys that stop the presenter.
final Set<LogicalKeyboardKey> _stopKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
  LogicalKeyboardKey.goBack,
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.browserBack,
};

class _OryksaPresenterViewState extends State<OryksaPresenterView> {
  @override
  void initState() {
    super.initState();
    // Early handler: runs before the focused widget, so the key stops her and is not passed on.
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
    widget.tv.presenter.addListener(_changed);
    widget.tv.addListener(_changed);
    widget.tv.configOrFallback();
  }

  @override
  void didUpdateWidget(OryksaPresenterView old) {
    super.didUpdateWidget(old);
    if (old.tv != widget.tv) {
      old.tv.presenter.removeListener(_changed);
      old.tv.removeListener(_changed);
      widget.tv.presenter.addListener(_changed);
      widget.tv.addListener(_changed);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    widget.tv.presenter.removeListener(_changed);
    widget.tv.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The key that stopped her: its release is swallowed too, so the app (or Android's Back)
  /// never sees half a key press.
  LogicalKeyboardKey? _swallowUp;

  KeyEventResult _onKey(KeyEvent e) {
    if (e is KeyUpEvent && e.logicalKey == _swallowUp) {
      _swallowUp = null;
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent && e.logicalKey == _swallowUp) return KeyEventResult.handled;
    if (!widget.remoteSkips || !widget.tv.presenter.isBusy || e is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_stopKeys.contains(e.logicalKey)) return KeyEventResult.ignored;
    _swallowUp = e.logicalKey;
    widget.tv.presenter.stop();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.tv.presenter;
    if (!p.isBusy && !widget.showWhenIdle) return const SizedBox.shrink();
    final m = OryksaTvMetrics.of(context);
    final th = widget.theme;
    final cfg = widget.tv.currentConfig;
    final name = cfg?.presenterName ?? 'ORYKSA';
    final avatar = cfg?.presenterAvatar ?? OryksaTvConfig.defaultAvatar;
    final speaking = p.phase == OryksaPresenterPhase.speaking;
    return Padding(
      padding: m.safe,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            OryksaTvAvatar(url: avatar, size: m.px(140), speaking: speaking, theme: th),
            SizedBox(width: m.px(28)),
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: m.px(36), vertical: m.px(24)),
                decoration: BoxDecoration(color: th.subtitleBackground, borderRadius: BorderRadius.circular(m.px(20))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontSize: m.small, color: th.accent, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    SizedBox(height: m.px(8)),
                    Text(
                      p.line,
                      key: const ValueKey('oryksa-tv-subtitle'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: m.subtitle, color: th.text, height: 1.25, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The QR to talk on the phone: the code, the short address and where it stands
/// (waiting, connected, listening, expired). Starts `tv.phoneVoice` when it appears
/// (unless [autoStart] is false). The phone page is from ORYKSA; the TV never needs a
/// microphone.
class OryksaPairingCard extends StatefulWidget {
  /// Creates the card for `tv.phoneVoice`.
  const OryksaPairingCard({super.key, required this.tv, this.autoStart = true, this.theme = const OryksaTvTheme()});

  /// The TV pieces.
  final OryksaTv tv;

  /// Starts the pairing when the card appears.
  final bool autoStart;

  /// Colours.
  final OryksaTvTheme theme;

  @override
  State<OryksaPairingCard> createState() => _OryksaPairingCardState();
}

class _OryksaPairingCardState extends State<OryksaPairingCard> {
  OryksaPhoneVoice get _pv => widget.tv.phoneVoice;

  @override
  void initState() {
    super.initState();
    _pv.addListener(_changed);
    widget.tv.addListener(_changed);
    widget.tv.configOrFallback();
    // After this frame: starting notifies the listeners, and a parent may be building now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autoStart && !_pv.isActive) _pv.start();
    });
  }

  @override
  void dispose() {
    _pv.removeListener(_changed);
    widget.tv.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final m = OryksaTvMetrics.of(context);
    final th = widget.theme;
    final cfg = widget.tv.currentConfig;
    final t = cfg?.texts ?? const OryksaTvTexts({});
    final p = _pv.pairing;
    final st = _pv.state;
    final ended = st == OryksaPhoneVoiceState.expired ||
        st == OryksaPhoneVoiceState.closed ||
        st == OryksaPhoneVoiceState.error ||
        st == OryksaPhoneVoiceState.phoneLeft;
    final status = switch (st) {
      OryksaPhoneVoiceState.idle || OryksaPhoneVoiceState.creating || OryksaPhoneVoiceState.waiting => t.get('pair_waiting'),
      OryksaPhoneVoiceState.paired => t.get('pair_connected'),
      OryksaPhoneVoiceState.listening => t.get('listening'),
      OryksaPhoneVoiceState.phoneLeft => t.get('phone_left'),
      OryksaPhoneVoiceState.expired => t.get('pair_expired'),
      OryksaPhoneVoiceState.closed || OryksaPhoneVoiceState.error => t.get('error'),
    };
    final qrSize = m.px(300);
    final showQr = p != null && !ended && st != OryksaPhoneVoiceState.paired && st != OryksaPhoneVoiceState.listening;
    return Container(
      padding: EdgeInsets.all(m.px(32)),
      decoration: BoxDecoration(color: th.surface, borderRadius: BorderRadius.circular(m.px(24))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showQr)
            Container(
              width: qrSize,
              height: qrSize,
              padding: EdgeInsets.all(m.px(16)),
              color: Colors.white,
              child: p.qrPngUrl.isEmpty
                  ? Center(
                      child: Text(p.code,
                          key: const ValueKey('oryksa-tv-qr-placeholder'),
                          style: TextStyle(fontSize: m.title, color: Colors.black, fontWeight: FontWeight.w800)),
                    )
                  : Image.network(p.qrPngUrl,
                      key: const ValueKey('oryksa-tv-qr'),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, __, ___) => Center(
                            child: Text(p.code, style: TextStyle(fontSize: m.title, color: Colors.black, fontWeight: FontWeight.w800)),
                          )),
            ),
          if (showQr) SizedBox(width: m.px(36)),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.get('pair_title'), style: TextStyle(fontSize: m.title, color: th.text, fontWeight: FontWeight.w800)),
                SizedBox(height: m.px(16)),
                if (showQr) ...[
                  Text(t.get('pair_step_scan'), style: TextStyle(fontSize: m.text, color: th.muted)),
                  SizedBox(height: m.px(8)),
                  Text(t.get('pair_step_code', {'url': p.shortUrl, 'code': p.code}),
                      style: TextStyle(fontSize: m.text, color: th.muted)),
                  SizedBox(height: m.px(16)),
                  Text(p.code,
                      key: const ValueKey('oryksa-tv-pair-code'),
                      style: TextStyle(fontSize: m.px(64), color: th.text, fontWeight: FontWeight.w800, letterSpacing: m.px(10))),
                  SizedBox(height: m.px(16)),
                ],
                Text(status, key: const ValueKey('oryksa-tv-pair-status'), style: TextStyle(fontSize: m.text, color: th.accent, fontWeight: FontWeight.w700)),
                if (_pv.lastText.isNotEmpty && !ended) ...[
                  SizedBox(height: m.px(8)),
                  Text('“${_pv.lastText}”', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: m.text, color: th.text)),
                ],
                if (ended) ...[
                  SizedBox(height: m.px(24)),
                  OryksaTvButton(label: t.get('retry'), icon: Icons.refresh_rounded, autofocus: true, theme: th, onPressed: _pv.restart),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
