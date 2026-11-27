import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'tv_core.dart';
import 'tv_models.dart';
import 'tv_phone_voice.dart';
import 'tv_widgets.dart';

/// Opens the assistant panel over your screen. Back closes it and the focus goes back where
/// it was. [sidePanel]: a panel on the right instead of the whole screen.
Future<void> showOryksaTvAssistant(
  BuildContext context, {
  required OryksaTv tv,
  OryksaAppContext? Function()? appContext,
  bool sidePanel = false,
  OryksaTvTheme theme = const OryksaTvTheme(),
}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: !sidePanel,
    barrierColor: sidePanel ? Colors.black54 : null,
    pageBuilder: (_, __, ___) => OryksaTvAssistant(tv: tv, appContext: appContext, sidePanel: sidePanel, theme: theme),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

/// The assistant panel: a conversation with the AI driven only by the remote (arrows, OK,
/// Back). The questions and buttons come from the server; the person can also talk on the
/// phone (QR) or type with the system keyboard. Replies are read by the presenter when the
/// server allows it.
///
/// Use [showOryksaTvAssistant], or place it in your layout and pass [onClose] (Back then
/// calls it instead of leaving your screen).
class OryksaTvAssistant extends StatefulWidget {
  /// Creates the panel.
  const OryksaTvAssistant({
    super.key,
    required this.tv,
    this.appContext,
    this.onClose,
    this.sidePanel = false,
    this.theme = const OryksaTvTheme(),
  });

  /// The TV pieces.
  final OryksaTv tv;

  /// The screen the person is on in your app (sent with each message).
  final OryksaAppContext? Function()? appContext;

  /// Called by Back and by the close button. Null: the panel pops its route.
  final VoidCallback? onClose;

  /// A panel on the right instead of the whole screen.
  final bool sidePanel;

  /// Colours.
  final OryksaTvTheme theme;

  @override
  State<OryksaTvAssistant> createState() => _OryksaTvAssistantState();
}

class _Msg {
  const _Msg(this.mine, this.text);
  final bool mine;
  final String text;
}

class _OryksaTvAssistantState extends State<OryksaTvAssistant> {
  final List<_Msg> _msgs = [];
  final List<String> _queue = [];
  final ScrollController _scroll = ScrollController();
  StreamSubscription<String>? _phoneSub;
  bool _busy = false;
  bool _showPairing = false;
  bool _spoke = false;
  OryksaTvConfig? _cfg;

  OryksaTv get tv => widget.tv;

  @override
  void initState() {
    super.initState();
    tv.addListener(_changed);
    tv.presenter.addListener(_changed);
    tv.phoneVoice.addListener(_changed);
    tv.configOrFallback().then((c) {
      if (mounted) setState(() => _cfg = c);
    });
    _phoneSub = tv.phoneVoice.texts.listen(_send);
  }

  @override
  void dispose() {
    tv.removeListener(_changed);
    tv.presenter.removeListener(_changed);
    tv.phoneVoice.removeListener(_changed);
    _phoneSub?.cancel();
    _scroll.dispose();
    if (_spoke && tv.presenter.isBusy) tv.presenter.stop();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _close() {
    if (_spoke && tv.presenter.isBusy) tv.presenter.stop();
    final c = widget.onClose;
    if (c != null) {
      c();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || !mounted) return;
    if (_busy) {
      _queue.add(t);
      return;
    }
    setState(() {
      _msgs.add(_Msg(true, t));
      _busy = true;
    });
    _toEnd();
    final cfg = await tv.configOrFallback();
    final speak = cfg.rules.speakReplies;
    var reply = '';
    String? speech;
    var ok = false;
    try {
      final r = await tv.backend.chat(t, locale: tv.locale, appContext: widget.appContext?.call(), voice: speak);
      reply = (r.reply ?? '').trim();
      speech = r.speech?.trim();
      ok = reply.isNotEmpty;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg(false, ok ? reply : cfg.texts.get('error')));
      _busy = false;
    });
    _toEnd();
    if (ok && speak) {
      _spoke = true;
      unawaited(tv.presenter.say((speech != null && speech.isNotEmpty) ? speech : reply));
    }
    if (_queue.isNotEmpty) unawaited(_send(_queue.removeAt(0)));
  }

  /// The system keyboard. Only the Send button sends: on the Fire TV, closing the keyboard
  /// with Back also "submits" the field (proven 26/11), and Back must mean cancel. The
  /// keyboard's own action (Next / Done) moves the focus to Send.
  Future<void> _type(OryksaTvTexts t) async {
    final text = await showDialog<String>(
      context: context,
      // What a screen reader says for the area around the dialog: the server's text, never a built-in English one.
      barrierLabel: t.get('close'),
      builder: (_) => _OryksaTvTypeDialog(texts: t, theme: widget.theme),
    );
    if (text != null) unawaited(_send(text));
  }

  String? _phoneStatus(OryksaTvTexts t) => switch (tv.phoneVoice.state) {
        OryksaPhoneVoiceState.paired => t.get('pair_connected'),
        OryksaPhoneVoiceState.listening => t.get('listening'),
        OryksaPhoneVoiceState.phoneLeft => t.get('phone_left'),
        _ => null,
      };

  void _action(OryksaTvAction a) {
    switch (a.kind) {
      case OryksaTvActionKind.message:
        _send(a.message ?? a.label);
      case OryksaTvActionKind.phoneVoice:
        setState(() => _showPairing = !_showPairing);
      case OryksaTvActionKind.close:
        _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = OryksaTvMetrics.of(context);
    final th = widget.theme;
    final cfg = tv.currentConfig ?? _cfg;
    final t = cfg?.texts ?? const OryksaTvTexts({});
    final name = cfg?.presenterName ?? 'ORYKSA';
    final phoneStatus = _showPairing ? null : _phoneStatus(t);
    final buttons = <Widget>[];
    void add(String label, VoidCallback onPressed, {IconData? icon}) {
      buttons.add(OryksaTvButton(label: label, icon: icon, theme: th, autofocus: buttons.isEmpty, onPressed: onPressed));
    }

    for (final s in cfg?.suggestions ?? const <String>[]) {
      add(s, () => _send(s));
    }
    final rules = cfg?.rules ?? const OryksaTvRules();
    for (final a in cfg?.actions ?? const <OryksaTvAction>[]) {
      if (a.kind == OryksaTvActionKind.phoneVoice && !rules.phoneVoice) continue;
      add(a.label, () => _action(a), icon: a.kind == OryksaTvActionKind.phoneVoice ? Icons.smartphone_rounded : null);
    }
    // The buttons wait for the configuration, so the first question gets the focus.
    if (cfg != null) {
      add(t.get('type_message'), () => _type(t), icon: Icons.keyboard_rounded);
      add(t.get('close'), _close, icon: Icons.close_rounded);
    }

    final panel = Container(
      color: th.background,
      padding: widget.sidePanel ? EdgeInsets.all(m.px(40)) : m.safe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OryksaTvAvatar(
                url: cfg?.presenterAvatar ?? OryksaTvConfig.defaultAvatar,
                size: m.px(96),
                speaking: tv.presenter.isBusy,
                theme: th,
              ),
              SizedBox(width: m.px(24)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.get('assistant_title'), style: TextStyle(fontSize: m.title, color: th.text, fontWeight: FontWeight.w800)),
                    SizedBox(height: m.px(6)),
                    Text(t.get('assistant_hint'), style: TextStyle(fontSize: m.small, color: th.muted)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: m.px(24)),
          Expanded(
            child: _Messages(
              msgs: _msgs,
              controller: _scroll,
              you: t.get('you'),
              ai: name,
              theme: th,
            ),
          ),
          if (_busy) ...[
            SizedBox(height: m.px(12)),
            Text(t.get('thinking'), key: const ValueKey('oryksa-tv-thinking'), style: TextStyle(fontSize: m.text, color: th.muted)),
          ],
          // Where the phone stands while the QR card is closed, in the chosen language: when the
          // phone leaves, the person sees it here (the phone button then gives a new code).
          if (phoneStatus != null) ...[
            SizedBox(height: m.px(12)),
            Text(phoneStatus,
                key: const ValueKey('oryksa-tv-phone-status'),
                style: TextStyle(fontSize: m.text, color: th.accent, fontWeight: FontWeight.w700)),
          ],
          if (_showPairing) ...[
            SizedBox(height: m.px(20)),
            Align(alignment: Alignment.centerLeft, child: OryksaPairingCard(tv: tv, theme: th)),
          ],
          SizedBox(height: m.px(24)),
          // One row that scrolls to the focused button: left and right always follow the order
          // of the buttons (a wrapped grid sends the arrows to unexpected places).
          FocusTraversalGroup(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(vertical: m.px(12)),
              child: Row(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) SizedBox(width: m.px(20)),
                    buttons[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final body = widget.sidePanel
        ? Align(alignment: Alignment.centerRight, child: SizedBox(width: math.max(m.size.width * 0.42, m.px(700)), child: panel))
        : panel;
    final content = Material(type: MaterialType.transparency, child: body);
    if (widget.onClose == null) return content;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: content,
    );
  }
}

/// The messages. When it has the focus, up and down scroll it; at the top or the bottom the
/// arrows move the focus out, as usual.
class _Messages extends StatefulWidget {
  const _Messages({required this.msgs, required this.controller, required this.you, required this.ai, required this.theme});

  final List<_Msg> msgs;
  final ScrollController controller;
  final String you;
  final String ai;
  final OryksaTvTheme theme;

  @override
  State<_Messages> createState() => _MessagesState();
}

class _MessagesState extends State<_Messages> {
  bool _focused = false;

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final c = widget.controller;
    if (!c.hasClients) return KeyEventResult.ignored;
    final pos = c.position;
    final step = pos.viewportDimension * 0.6;
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && pos.pixels > pos.minScrollExtent + 1) {
      c.animateTo(math.max(pos.minScrollExtent, pos.pixels - step), duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && pos.pixels < pos.maxScrollExtent - 1) {
      c.animateTo(math.min(pos.maxScrollExtent, pos.pixels + step), duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final m = OryksaTvMetrics.of(context);
    final th = widget.theme;
    return Focus(
      canRequestFocus: widget.msgs.isNotEmpty,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _key,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(m.px(20)),
          border: Border.all(color: _focused ? th.focus : Colors.transparent, width: m.focusWidth),
        ),
        padding: EdgeInsets.all(m.px(12)),
        child: ListView.builder(
          controller: widget.controller,
          itemCount: widget.msgs.length,
          itemBuilder: (_, i) {
            final msg = widget.msgs[i];
            return Align(
              alignment: msg.mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                key: ValueKey('oryksa-tv-msg-$i'),
                constraints: BoxConstraints(maxWidth: m.size.width * (msg.mine ? 0.5 : 0.7)),
                margin: EdgeInsets.only(bottom: m.px(16)),
                padding: EdgeInsets.symmetric(horizontal: m.px(28), vertical: m.px(18)),
                decoration: BoxDecoration(
                  color: msg.mine ? th.accent.withValues(alpha: 0.35) : th.surface,
                  borderRadius: BorderRadius.circular(m.px(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(msg.mine ? widget.you : widget.ai,
                        style: TextStyle(fontSize: m.small, color: th.muted, fontWeight: FontWeight.w700)),
                    SizedBox(height: m.px(6)),
                    Text(msg.text, style: TextStyle(fontSize: m.text, color: th.text, height: 1.3)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The typing dialog. It owns its field and its focus nodes and frees them only when the dialog
/// is gone for good: its closing animation still builds the field (seen with a screen reader on).
class _OryksaTvTypeDialog extends StatefulWidget {
  const _OryksaTvTypeDialog({required this.texts, required this.theme});

  final OryksaTvTexts texts;
  final OryksaTvTheme theme;

  @override
  State<_OryksaTvTypeDialog> createState() => _OryksaTvTypeDialogState();
}

class _OryksaTvTypeDialogState extends State<_OryksaTvTypeDialog> {
  final _ctrl = TextEditingController();
  final _sendFocus = FocusNode(debugLabel: 'oryksa-tv-send');
  final _fieldFocus = FocusNode(debugLabel: 'oryksa-tv-type-field');

  @override
  void initState() {
    super.initState();
    _fieldFocus.addListener(_onFieldFocus);
  }

  // When the keyboard closes the field loses the focus and nothing has it: give it to Send,
  // so the remote keeps working. After the frame, when the focus has settled. Not while the
  // dialog is closing: the focus then goes back to the panel.
  void _onFieldFocus() {
    if (_fieldFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
      final p = FocusManager.instance.primaryFocus;
      if (_sendFocus.context != null && (p == null || p is FocusScopeNode)) _sendFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _fieldFocus.removeListener(_onFieldFocus);
    _ctrl.dispose();
    _sendFocus.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = OryksaTvMetrics.of(context);
    final th = widget.theme;
    final t = widget.texts;
    return Dialog(
      backgroundColor: th.surface,
      child: Padding(
        padding: EdgeInsets.all(m.px(32)),
        child: SizedBox(
          width: m.size.width * 0.6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('oryksa-tv-type-field'),
                controller: _ctrl,
                focusNode: _fieldFocus,
                autofocus: true,
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: m.text, color: th.text),
                cursorColor: th.accent,
                decoration: InputDecoration(hintText: t.get('type_message'), hintStyle: TextStyle(fontSize: m.text, color: th.muted)),
                // After the frame: the field unfocuses itself right after this callback,
                // which would cancel a focus request made now.
                onSubmitted: (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _sendFocus.context != null) _sendFocus.requestFocus();
                }),
              ),
              SizedBox(height: m.px(24)),
              Row(
                children: [
                  OryksaTvButton(
                    label: t.get('send'),
                    icon: Icons.send_rounded,
                    focusNode: _sendFocus,
                    theme: th,
                    onPressed: () {
                      final v = _ctrl.text.trim();
                      if (v.isNotEmpty) Navigator.of(context).pop(v);
                    },
                  ),
                  SizedBox(width: m.px(20)),
                  OryksaTvButton(label: t.get('close'), icon: Icons.close_rounded, theme: th, onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
