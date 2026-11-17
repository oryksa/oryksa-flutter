import 'package:flutter/material.dart';

import 'chat.dart';
import 'client.dart';
import 'models.dart';

/// The round button with the photo of the AI for the middle of a bottom tab bar,
/// the same as in the ORYKSA app. Tapping it opens the chat (with voice) with
/// [showOryksaChatScreen]: a full screen on phones, a side panel on wide screens.
///
/// The name and photo come from "Your AI" in the ORYKSA account. When the business
/// picks "Company logo" in the ORYKSA panel (Connectors > Website chat), the bubble
/// shows the company logo and the business name instead; the chat that opens keeps
/// the photo and name of the AI. Use it inside [OryksaBottomBar], or put it in the
/// middle of your own bar (see the README).
class OryksaTabBubble extends StatefulWidget {
  /// Creates the bubble.
  const OryksaTabBubble({
    super.key,
    required this.client,
    this.lang,
    this.theme,
    this.appContext,
    this.voice = true,
    this.onPickImage,
    this.size = 64,
    this.unread = false,
    this.showLabel = false,
    this.label,
    this.labelStyle,
    this.borderColor,
    this.onOpen,
    this.onTap,
    this.image,
  });

  /// Client with the session token.
  final OryksaClient client;

  /// `en`, `pt`, `br` or `es` (or a locale tag such as `pt-BR`). Null: the app locale.
  final String? lang;

  /// Colors of the bubble ring and of the chat. Null: light or dark from the app theme.
  final OryksaChatTheme? theme;

  /// Where the customer is in your app right now (sent with each message).
  final OryksaAppContext? Function()? appContext;

  /// Shows the microphone in the chat when the plan has voice.
  final bool voice;

  /// Shows a photo button in the chat. Return the photo the customer picked (for example
  /// with the `image_picker` package), or null when they cancel. The AI looks at the photo.
  final Future<OryksaImage?> Function()? onPickImage;

  /// Diameter of the bubble with its ring, in dp (64 by default, 48 at least).
  final double size;

  /// Shows a dot on the bubble: there is a reply the customer has not seen. Your
  /// app decides it (for example from a push of your server after the ORYKSA
  /// `message.replied` webhook) and clears it in [onOpen].
  final bool unread;

  /// Shows the name of the AI (or the business name with the company logo, or
  /// [label]) under the bubble.
  final bool showLabel;

  /// Text under the bubble. By default the label chosen in the ORYKSA panel
  /// ([OryksaAgent.launcherLabel]: the business name with the company logo),
  /// else the name of the AI.
  final String? label;

  /// Style of the text under the bubble.
  final TextStyle? labelStyle;

  /// Color of the outer edge of the bubble. Use the color of your bar so the bubble
  /// looks cut into it. Null: the surface color of the app theme.
  final Color? borderColor;

  /// Called on every tap, before the chat opens (for example to clear [unread]).
  final VoidCallback? onOpen;

  /// Replaces what the tap does (by default it opens the chat).
  final VoidCallback? onTap;

  /// Image shown in the bubble, over what the ORYKSA panel chose, for example
  /// `AssetImage('assets/logo.png')`. It is drawn whole (not cropped) on white, as
  /// a logo. Null: the company logo when the business picked it in the ORYKSA
  /// panel, else the photo of the AI. The chat that opens keeps the photo of the AI.
  final ImageProvider? image;

  @override
  State<OryksaTabBubble> createState() => _OryksaTabBubbleState();
}

class _OryksaTabBubbleState extends State<OryksaTabBubble> {
  OryksaAgent? _agent;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  @override
  void didUpdateWidget(OryksaTabBubble old) {
    super.didUpdateWidget(old);
    if (!identical(old.client, widget.client)) {
      _agent = null;
      _loadAgent();
    }
  }

  void _loadAgent() {
    widget.client.agent().then((a) {
      if (mounted) setState(() => _agent = a);
    }).catchError((Object _) {});
  }

  Future<void> _tap() async {
    widget.onOpen?.call();
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    if (_opening) return;
    _opening = true;
    try {
      // What the bubble opens comes from the ORYKSA panel (Connectors > Website chat > Open in):
      // the voice screen by default, or the text chat.
      OryksaAgent? a = _agent;
      if (a == null) {
        try {
          a = await widget.client.agent();
          if (mounted) setState(() => _agent = a);
        } catch (_) {
          a = null;
        }
      }
      if (!mounted) return;
      await showOryksaChatScreen(context,
          client: widget.client,
          lang: widget.lang,
          theme: widget.theme,
          appContext: widget.appContext,
          voice: widget.voice,
          onPickImage: widget.onPickImage,
          startInVoice: widget.voice && (a?.openMode ?? 'voice') == 'voice');
    } finally {
      _opening = false;
    }
    if (mounted && _agent == null) _loadAgent();
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.theme ?? OryksaChatTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = oryksaChatTexts(oryksaLangOf(context, widget.lang));
    final name = _agent?.name ?? 'ORYKSA';
    final semantic = '${t['talk']} $name${widget.unread ? ', ${t['unread']}' : ''}';
    final size = widget.size < 48 ? 48.0 : widget.size;
    final edge = widget.borderColor ?? scheme.surface;
    final border = size * .065;
    final ring = size * .05;
    final photo = size - 2 * (border + ring);
    final dot = size * .22;

    // What the bubble shows: the image of the app, else the company logo chosen in
    // the ORYKSA panel, else the photo of the AI (as 1.2.0). The chat keeps the AI.
    final agent = _agent;
    final logoUrl = agent != null && agent.launcherIcon == 'logo' ? agent.launcherImage : null;
    final ImageProvider? picture = widget.image ??
        (logoUrl != null && logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null) ??
        (agent == null ? null : NetworkImage(agent.avatar));
    final isLogo = widget.image != null || (logoUrl != null && logoUrl.isNotEmpty);
    final placeholder = _Placeholder(color: th.soft, icon: th.accent);
    final Widget face;
    if (picture == null) {
      face = placeholder;
    } else if (isLogo) {
      // A logo is drawn whole on white with some room around it, so a logo that is
      // not round is not cropped. The frame builder does not run on an error, so then
      // the placeholder fills the circle, as for the photo.
      face = Image(
        image: picture,
        fit: BoxFit.contain,
        frameBuilder: (_, child, __, ___) => ColoredBox(
          color: Colors.white,
          child: Padding(padding: EdgeInsets.all(photo * .12), child: child),
        ),
        errorBuilder: (_, __, ___) => placeholder,
      );
    } else {
      face = Image(image: picture, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
    }

    final circle = SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(ring),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [Color.lerp(th.accent, Colors.white, .28)!, th.accent],
            ),
            border: Border.all(color: edge, width: border),
            boxShadow: [BoxShadow(color: th.accent.withValues(alpha: .38), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: ClipOval(
            child: SizedBox(width: photo, height: photo, child: face),
          ),
        ),
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(customBorder: const CircleBorder(), onTap: _tap, excludeFromSemantics: true),
          ),
        ),
        if (widget.unread)
          PositionedDirectional(
            top: size * .02,
            end: size * .02,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('oryksa-unread-dot'),
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D),
                  shape: BoxShape.circle,
                  border: Border.all(color: edge, width: dot * .18),
                ),
              ),
            ),
          ),
      ]),
    );

    final launcherLabel = agent?.launcherLabel;
    final label = widget.label ?? (launcherLabel != null && launcherLabel.isNotEmpty ? launcherLabel : null) ?? agent?.name ?? '';
    return Semantics(
      container: true,
      button: true,
      label: semantic,
      onTap: _tap,
      excludeSemantics: true,
      child: Tooltip(
        message: semantic,
        excludeFromSemantics: true,
        child: !widget.showLabel
            ? circle
            : Column(mainAxisSize: MainAxisSize.min, children: [
                circle,
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.5,
                  child: SizedBox(
                    width: size + 24,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.labelStyle ??
                          (Theme.of(context).textTheme.labelMedium ?? const TextStyle(fontSize: 12))
                              .copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ]),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.color, required this.icon});
  final Color color;
  final Color icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: color,
        child: Center(child: Icon(Icons.chat_bubble_rounded, color: icon, size: 22)),
      );
}

/// A bottom tab bar with your destinations and the AI bubble ([OryksaTabBubble])
/// in the middle, in the Material 3 [NavigationBar] style. It takes the same
/// [NavigationDestination] items, [selectedIndex] and [onDestinationSelected], so
/// moving from a [NavigationBar] is one line:
///
/// ```dart
/// bottomNavigationBar: OryksaBottomBar(
///   client: client,
///   selectedIndex: tab,
///   onDestinationSelected: (i) => setState(() => tab = i),
///   destinations: const [ /* the same NavigationDestination items */ ],
/// ),
/// ```
///
/// [selectedIndex] counts only your destinations (the bubble is not a tab). With
/// an odd number of destinations the extra one goes before the bubble.
class OryksaBottomBar extends StatelessWidget {
  /// Creates the bar.
  const OryksaBottomBar({
    super.key,
    required this.client,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.lang,
    this.theme,
    this.appContext,
    this.voice = true,
    this.onPickImage,
    this.unread = false,
    this.onBubbleOpen,
    this.onBubbleTap,
    this.bubbleLabel,
    this.bubbleImage,
    this.showBubbleLabel = true,
    this.backgroundColor,
    this.indicatorColor,
    this.height = 80,
    this.raise = 14,
    this.bubbleSize = 64,
  }) : assert(destinations.length >= 2, 'OryksaBottomBar needs at least 2 destinations.');

  /// Client with the session token.
  final OryksaClient client;

  /// Your tabs (the same [NavigationDestination] items as a [NavigationBar]).
  final List<NavigationDestination> destinations;

  /// The selected destination (the bubble is not counted).
  final int selectedIndex;

  /// Called with the index of the destination tapped.
  final ValueChanged<int> onDestinationSelected;

  /// `en`, `pt`, `br` or `es` (or a locale tag such as `pt-BR`). Null: the app locale.
  final String? lang;

  /// Colors of the bubble and of the chat. Null: light or dark from the app theme.
  final OryksaChatTheme? theme;

  /// Where the customer is in your app right now (sent with each message).
  final OryksaAppContext? Function()? appContext;

  /// Shows the microphone in the chat when the plan has voice.
  final bool voice;

  /// Shows a photo button in the chat. Return the photo the customer picked (for example
  /// with the `image_picker` package), or null when they cancel. The AI looks at the photo.
  final Future<OryksaImage?> Function()? onPickImage;

  /// Shows the unread dot on the bubble (see [OryksaTabBubble.unread]).
  final bool unread;

  /// Called on every tap of the bubble, before the chat opens.
  final VoidCallback? onBubbleOpen;

  /// Replaces what a tap on the bubble does (by default it opens the chat).
  final VoidCallback? onBubbleTap;

  /// Text under the bubble. By default the label chosen in the ORYKSA panel (the
  /// business name with the company logo), else the name of the AI.
  final String? bubbleLabel;

  /// Image shown in the bubble, over what the ORYKSA panel chose (see
  /// [OryksaTabBubble.image]), for example `AssetImage('assets/logo.png')`. Null:
  /// the company logo or the photo of the AI, as chosen in the ORYKSA panel.
  final ImageProvider? bubbleImage;

  /// Shows the text under the bubble.
  final bool showBubbleLabel;

  /// Bar color. Null: the [NavigationBarTheme] color, then `surfaceContainer`.
  final Color? backgroundColor;

  /// Color of the pill behind the selected icon. Null: the [NavigationBarTheme]
  /// color, then `secondaryContainer`.
  final Color? indicatorColor;

  /// Height of the bar without the safe area (80, as the Material 3 bar).
  final double height;

  /// How far the bubble rises above the bar (0 keeps it inside).
  final double raise;

  /// Diameter of the bubble with its ring.
  final double bubbleSize;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    final cs = appTheme.colorScheme;
    final nb = NavigationBarTheme.of(context);
    final bg = backgroundColor ?? nb.backgroundColor ?? cs.surfaceContainer;
    final ind = indicatorColor ?? nb.indicatorColor ?? cs.secondaryContainer;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final n = destinations.length;
    final mid = (n + 1) ~/ 2;
    final labelBase = appTheme.textTheme.labelMedium ?? const TextStyle(fontSize: 12);
    final tabLabels = MaterialLocalizations.of(context);

    Widget item(int i) {
      final d = destinations[i];
      final sel = i == selectedIndex;
      final on = d.enabled;
      final color = !on
          ? cs.onSurfaceVariant.withValues(alpha: .38)
          : sel
              ? cs.onSecondaryContainer
              : cs.onSurfaceVariant;
      return Semantics(
        container: true,
        button: true,
        selected: sel,
        enabled: on,
        label: '${d.label}\n${tabLabels.tabLabel(tabIndex: i + 1, tabCount: n)}',
        onTap: on ? () => onDestinationSelected(i) : null,
        excludeSemantics: true,
        child: Padding(
          padding: EdgeInsets.only(top: raise),
          child: InkWell(
            key: ValueKey('oryksa-tab-$i'),
            onTap: on ? () => onDestinationSelected(i) : null,
            excludeFromSemantics: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 64,
                  height: 32,
                  decoration: BoxDecoration(color: sel ? ind : ind.withValues(alpha: 0), borderRadius: BorderRadius.circular(16)),
                  child: IconTheme.merge(
                    data: IconThemeData(color: color, size: 24),
                    child: Center(child: sel ? (d.selectedIcon ?? d.icon) : d.icon),
                  ),
                ),
                const SizedBox(height: 4),
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelBase.copyWith(
                      color: !on ? color : (sel ? cs.onSurface : cs.onSurfaceVariant),
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    final bubble = Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OryksaTabBubble(
          client: client,
          lang: lang,
          theme: theme,
          appContext: appContext,
          voice: voice,
          onPickImage: onPickImage,
          size: bubbleSize,
          unread: unread,
          showLabel: showBubbleLabel,
          label: bubbleLabel,
          image: bubbleImage,
          borderColor: bg,
          onOpen: onBubbleOpen,
          onTap: onBubbleTap,
        ),
      ),
    );

    return SizedBox(
      height: raise + height + bottom,
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: raise,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -1))],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Material(
            type: MaterialType.transparency,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < mid; i++) Expanded(child: item(i)),
              Expanded(child: bubble),
              for (var i = mid; i < n; i++) Expanded(child: item(i)),
            ]),
          ),
        ),
      ]),
    );
  }
}
