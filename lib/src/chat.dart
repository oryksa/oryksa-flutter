import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client.dart';
import 'models.dart';
import 'profanity.dart';
import 'voice.dart';
import 'voice_screen.dart';

/// Colors of the chat. The defaults are the ORYKSA website chat colors.
///
/// [OryksaChatTheme.dark] is the dark version. The tab bar bubble and its chat
/// pick the light or dark one from the app theme when no theme is given
/// ([OryksaChatTheme.of]).
class OryksaChatTheme {
  /// Creates a theme (light).
  const OryksaChatTheme({
    this.accent = const Color(0xFF5B57E0),
    this.ink = const Color(0xFF161B3D),
    this.soft = const Color(0xFFEEEBFB),
    this.background = Colors.white,
    this.muted = const Color(0xFF6B7280),
    this.line = const Color(0xFFECEEF6),
  });

  /// The dark theme (the ORYKSA app dark colors).
  const OryksaChatTheme.dark({
    this.accent = const Color(0xFF7D79F0),
    this.ink = const Color(0xFFECEEFB),
    this.soft = const Color(0xFF262C4D),
    this.background = const Color(0xFF141A30),
    this.muted = const Color(0xFF9AA2C6),
    this.line = const Color(0xFF2B3154),
  });

  /// The light or the dark default theme, following the app theme of [context].
  static OryksaChatTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const OryksaChatTheme.dark() : const OryksaChatTheme();

  /// Buttons, visitor bubbles and links.
  final Color accent;

  /// Main text.
  final Color ink;

  /// AI bubbles.
  final Color soft;

  /// Panel background.
  final Color background;

  /// Secondary text.
  final Color muted;

  /// Dividers and outlines.
  final Color line;
}

const Map<String, Map<String, String>> _tx = {
  'en': {'talk': 'Talk to', 'ph': 'Type your question', 'send': 'Send', 'err': 'Sorry, something went wrong. Try again.', 'voice': 'Talk by voice', 'copy': 'Copy', 'unread': 'new message', 'photo': 'Send a photo'},
  'pt': {'talk': 'Falar com', 'ph': 'Escreve a tua pergunta', 'send': 'Enviar', 'err': 'Desculpa, algo correu mal. Tenta de novo.', 'voice': 'Falar por voz', 'copy': 'Copiar', 'unread': 'nova mensagem', 'photo': 'Enviar uma foto'},
  'br': {'talk': 'Falar com', 'ph': 'Digite sua pergunta', 'send': 'Enviar', 'err': 'Desculpe, algo deu errado. Tente de novo.', 'voice': 'Falar por voz', 'copy': 'Copiar', 'unread': 'nova mensagem', 'photo': 'Enviar uma foto'},
  'es': {'talk': 'Hablar con', 'ph': 'Escribe tu pregunta', 'send': 'Enviar', 'err': 'Lo siento, algo salió mal. Inténtalo de nuevo.', 'voice': 'Hablar por voz', 'copy': 'Copiar', 'unread': 'mensaje nuevo', 'photo': 'Enviar una foto'},
};

/// The SDK language for a language code or locale tag: `en`, `pt`, `br` (Portuguese
/// of Brazil) or `es`. Accepts `pt-BR`, `pt_BR`, `pt-PT`, `es-ES`, `en-GB`...;
/// anything else is `en`.
String oryksaLang(String? lang) {
  final l = (lang ?? '').trim().toLowerCase().replaceAll('_', '-');
  if (l == 'br' || l == 'pt-br') return 'br';
  if (l == 'pt' || l.startsWith('pt-')) return 'pt';
  if (l == 'es' || l.startsWith('es-')) return 'es';
  return 'en';
}

/// The SDK language of the app: [lang] when given, otherwise the locale of [context].
String oryksaLangOf(BuildContext context, [String? lang]) {
  if (lang != null && lang.trim().isNotEmpty) return oryksaLang(lang);
  final loc = Localizations.maybeLocaleOf(context);
  return oryksaLang(loc?.toLanguageTag());
}

/// Texts of the chat for [lang] (`en`, `pt`, `br`, `es`).
Map<String, String> oryksaChatTexts(String lang) => _tx[oryksaLang(lang)]!;

String _lang(String l) => oryksaLang(l);

/// The ORYKSA chat panel: header with the photo and name of the AI, messages,
/// suggested questions and the input. Same look as the ORYKSA website chat.
class OryksaChat extends StatefulWidget {
  /// Creates the chat panel.
  const OryksaChat({
    super.key,
    required this.client,
    this.lang = 'en',
    this.theme = const OryksaChatTheme(),
    this.onClose,
    this.appContext,
    this.voice = true,
    this.onPickImage,
  });

  /// Client with the session token.
  final OryksaClient client;

  /// Where the customer is in your app right now (for example the product on
  /// screen). Sent with each message so the AI answers about it.
  final OryksaAppContext? Function()? appContext;

  /// Shows the microphone button (voice conversation) when the plan has voice.
  /// Needs the microphone permission in the app (see the README).
  final bool voice;

  /// Shows a photo button in the chat. Return the photo the customer picked (for example
  /// with the `image_picker` package), or null when they cancel. The AI looks at the photo.
  final Future<OryksaImage?> Function()? onPickImage;

  /// `en`, `pt`, `br` or `es` (locale tags such as `pt-BR` or `es-ES` work too).
  final String lang;

  /// Colors.
  final OryksaChatTheme theme;

  /// Shows a close button that calls this.
  final VoidCallback? onClose;

  @override
  State<OryksaChat> createState() => _OryksaChatState();
}

class _Msg {
  _Msg(this.role, this.text, [this.image]);
  final String role; // user | assistant | typing
  final String text;
  final Uint8List? image;
}

class _OryksaChatState extends State<OryksaChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  List<String> _sug = [];
  OryksaAgent? _agent;
  bool _busy = false;

  Map<String, String> get t => _tx[_lang(widget.lang)]!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Swear words the customer types show as asterisks (one list for every ORYKSA chat).
    OryksaProfanity.load(_lang(widget.lang)).then((_) {
      if (mounted) setState(() {});
    });
    try {
      final a = await widget.client.agent();
      if (!mounted) return;
      final hist = await widget.client.messages().catchError((_) => <OryksaMessage>[]);
      if (!mounted) return;
      setState(() {
        _agent = a;
        if (hist.isNotEmpty) {
          _msgs.addAll(hist.map((m) => _Msg(m.role == 'user' ? 'user' : 'assistant', m.content)));
        } else {
          final g = OryksaAgent.pick(a.greeting, _lang(widget.lang));
          if (g != null && g.isNotEmpty) _msgs.add(_Msg('assistant', g));
          _sug = (OryksaAgent.pick(a.suggestions, _lang(widget.lang)) ?? const <String>[]).take(4).toList();
        }
      });
      _toEnd();
    } catch (_) {
      if (mounted) setState(() => _agent = const OryksaAgent(name: 'ORYKSA', avatar: 'https://oryksa.com/assets/img/avatar_official_oryksa.png'));
    }
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickAndSend() async {
    final pick = widget.onPickImage;
    if (pick == null || _busy) return;
    OryksaImage? img;
    try {
      img = await pick();
    } catch (_) {
      img = null;
    }
    if (img == null || !mounted) return;
    await _send(_input.text, image: img);
  }

  Future<void> _send(String text, {OryksaImage? image}) async {
    text = text.trim();
    if ((text.isEmpty && image == null) || _busy) return;
    setState(() {
      _busy = true;
      _sug = [];
      _msgs.add(_Msg('user', text, image?.bytes));
      _msgs.add(_Msg('typing', '...'));
      _input.clear();
    });
    _toEnd();
    String? reply;
    try {
      reply = await widget.client.sendAndWait(text, appContext: widget.appContext?.call(), lang: _lang(widget.lang), image: image);
    } catch (_) {
      reply = null;
    }
    if (!mounted) return;
    setState(() {
      _msgs.removeWhere((m) => m.role == 'typing');
      _msgs.add(_Msg('assistant', (reply == null || reply.isEmpty) ? t['err']! : reply));
      _busy = false;
    });
    _toEnd();
  }

  Future<void> _openVoice() async {
    final a = _agent;
    if (a == null) return;
    final ctl = OryksaVoiceController(
      client: widget.client,
      appContext: widget.appContext,
      lang: _lang(widget.lang),
      onUserText: (s) {
        if (!mounted) return;
        setState(() {
          _sug = [];
          _msgs.add(_Msg('user', s));
        });
        _toEnd();
      },
      onReply: (s) {
        if (!mounted) return;
        setState(() => _msgs.add(_Msg('assistant', s)));
        _toEnd();
      },
    );
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => OryksaVoiceScreen(controller: ctl, agent: a, lang: _lang(widget.lang), theme: widget.theme),
    ));
    ctl.dispose();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.theme;
    final a = _agent;
    final sub = a == null ? '' : (OryksaAgent.pick(a.subtitle, _lang(widget.lang)) ?? a.business ?? '');
    return Material(
      color: th.background,
      child: Column(children: [
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: th.line))),
          child: Row(children: [
            _Avatar(url: a?.avatar, size: 46, placeholder: th.soft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((a?.name ?? '').toUpperCase(),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 2, color: th.ink)),
                if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12, color: th.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (widget.onClose != null)
              IconButton(onPressed: widget.onClose, icon: Icon(Icons.close, color: th.muted), tooltip: MaterialLocalizations.of(context).closeButtonTooltip),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, box) => ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _msgs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final m = _msgs[i];
              final mine = m.role == 'user';
              final bubble = Align(
                alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * .78),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: mine ? th.accent : th.soft,
                      borderRadius: BorderRadiusDirectional.only(
                        topStart: const Radius.circular(16),
                        topEnd: const Radius.circular(16),
                        bottomStart: Radius.circular(mine ? 16 : 6),
                        bottomEnd: Radius.circular(mine ? 6 : 16),
                      ),
                    ),
                    child: Opacity(
                      opacity: m.role == 'typing' ? .6 : 1,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        if (m.image != null)
                          Padding(
                            padding: EdgeInsets.only(bottom: m.text.isEmpty ? 0 : 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(m.image!, height: 160, fit: BoxFit.cover, semanticLabel: t['photo']),
                            ),
                          ),
                        if (m.text.isNotEmpty)
                          SelectableText.rich(
                            TextSpan(
                                children: oryksaBold(mine ? OryksaProfanity.mask(m.text, _lang(widget.lang)) : m.text,
                                    TextStyle(fontSize: 14, height: 1.5, color: mine ? Colors.white : th.ink))),
                          ),
                      ]),
                    ),
                  ),
                ),
              );
              if (mine || m.role == 'typing' || m.text.trim().isEmpty) return bubble;
              // Copy button under each reply of the AI (same as the ORYKSA apps and extension).
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                bubble,
                _CopyButton(text: m.text.replaceAll('**', ''), label: _tx[_lang(widget.lang)]!['copy']!, color: th.muted),
              ]);
            },
          )),
        ),
        if (_sug.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in _sug)
                OutlinedButton(
                  onPressed: () => _send(s),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: th.accent,
                    side: BorderSide(color: th.line),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                  child: Text(s),
                ),
            ]),
          ),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: th.line))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 14, color: th.ink),
                decoration: InputDecoration(
                  hintText: t['ph'],
                  hintStyle: TextStyle(fontSize: 14, color: th.muted),
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            if (widget.onPickImage != null)
              IconButton(
                onPressed: _busy ? null : _pickAndSend,
                tooltip: t['photo'],
                icon: Icon(Icons.photo_camera_outlined, color: th.accent),
              ),
            if (widget.voice && (a?.voiceReplies ?? false) && _input.text.trim().isEmpty)
              IconButton(
                onPressed: _busy ? null : _openVoice,
                tooltip: t['voice'],
                icon: Icon(Icons.mic_none, color: th.accent),
              ),
            SizedBox(
              height: 50,
              child: TextButton(
                onPressed: _busy ? null : () => _send(_input.text),
                style: TextButton.styleFrom(
                  backgroundColor: th.accent,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: Text(t['send']!.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'POWERED BY '),
              TextSpan(text: 'ORYKSA', style: TextStyle(color: th.accent, fontWeight: FontWeight.w800)),
            ]),
            style: const TextStyle(fontSize: 10.5, letterSpacing: 1.3, color: Color(0xFF9CA3AF)),
          ),
        ),
      ]),
    );
  }
}

/// Text with **bold** parts (the server marks them, the app only draws them).
List<TextSpan> oryksaBold(String text, TextStyle base) {
  final parts = text.split('**');
  if (parts.length < 3) return [TextSpan(text: text, style: base)];
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty) TextSpan(text: parts[i], style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w700) : base),
  ];
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size, this.placeholder = const Color(0xFFEEEBFB)});
  final String? url;
  final double size;
  final Color placeholder;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? ColoredBox(color: placeholder)
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: placeholder)),
      ),
    );
  }
}

/// Opens the ORYKSA chat: a bottom sheet on phones, a floating panel on wide screens.
Future<void> showOryksaChat(
  BuildContext context, {
  required OryksaClient client,
  String lang = 'en',
  OryksaChatTheme theme = const OryksaChatTheme(),
  bool alignLeft = false,
  OryksaAppContext? Function()? appContext,
  bool voice = true,
  Future<OryksaImage?> Function()? onPickImage,
}) {
  final wide = MediaQuery.of(context).size.width >= 600;
  if (!wide) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .88,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: OryksaChat(client: client, lang: lang, theme: theme, appContext: appContext, voice: voice, onPickImage: onPickImage, onClose: () => Navigator.of(ctx).pop()),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => Align(
      alignment: alignLeft ? Alignment.bottomLeft : Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 92),
        child: Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 380,
            height: 560,
            child: OryksaChat(client: client, lang: lang, theme: theme, appContext: appContext, voice: voice, onPickImage: onPickImage, onClose: () => Navigator.of(ctx).pop()),
          ),
        ),
      ),
    ),
  );
}

/// From this width (in logical pixels, dp) the tab bar bubble opens the chat as a
/// side panel instead of a full screen: tablets, open foldables and desktop.
const double oryksaWideBreakpoint = 840;

/// Opens the ORYKSA chat the way the tab bar bubble does ([OryksaTabBubble]):
///
/// * phones (narrower than [oryksaWideBreakpoint]): a full screen page;
/// * wide screens: a side panel at the end of the screen (the right in
///   left-to-right languages), so the app stays visible beside the chat.
///
/// [lang] is `en`, `pt`, `br` or `es` (or a locale tag such as `pt-BR`); when it
/// is null the app locale is used. [theme] null follows the app light or dark theme.
Future<void> showOryksaChatScreen(
  BuildContext context, {
  required OryksaClient client,
  String? lang,
  OryksaChatTheme? theme,
  OryksaAppContext? Function()? appContext,
  bool voice = true,
  Future<OryksaImage?> Function()? onPickImage,
  double panelWidth = 420,
}) {
  final l = oryksaLangOf(context, lang);
  final th = theme ?? OryksaChatTheme.of(context);
  if (MediaQuery.sizeOf(context).width < oryksaWideBreakpoint) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      settings: const RouteSettings(name: 'oryksa-chat'),
      builder: (ctx) => Scaffold(
        backgroundColor: th.background,
        body: SafeArea(
          child: OryksaChat(
              client: client, lang: l, theme: th, appContext: appContext, voice: voice, onPickImage: onPickImage, onClose: () => Navigator.of(ctx).maybePop()),
        ),
      ),
    ));
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black12,
    transitionDuration: const Duration(milliseconds: 240),
    routeSettings: const RouteSettings(name: 'oryksa-chat'),
    transitionBuilder: (_, __, ___, child) => child,
    pageBuilder: (ctx, anim, _) {
      final rtl = Directionality.of(ctx) == TextDirection.rtl;
      final size = MediaQuery.sizeOf(ctx);
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SlideTransition(
          position: Tween<Offset>(begin: Offset(rtl ? -1 : 1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: Material(
            elevation: 16,
            color: th.background,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(20))),
            child: SizedBox(
              width: math.min(panelWidth, size.width * .5),
              height: size.height,
              child: SafeArea(
                left: rtl,
                right: !rtl,
                child: Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
                  child: OryksaChat(
                      client: client, lang: l, theme: th, appContext: appContext, voice: voice, onPickImage: onPickImage, onClose: () => Navigator.of(ctx).pop()),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Floating "Talk to `name`" button with the photo of the AI. Put it in a [Stack]
/// (or as a [Scaffold.floatingActionButton]); tapping it opens [showOryksaChat].
class OryksaChatButton extends StatefulWidget {
  /// Creates the button.
  const OryksaChatButton({
    super.key,
    required this.client,
    this.lang = 'en',
    this.theme = const OryksaChatTheme(),
    this.alignLeft = false,
    this.appContext,
    this.voice = true,
    this.onPickImage,
  });

  /// Where the customer is in your app right now (sent with each message).
  final OryksaAppContext? Function()? appContext;

  /// Shows the microphone in the chat when the plan has voice.
  final bool voice;

  /// Shows a photo button in the chat. Return the photo the customer picked (for example
  /// with the `image_picker` package), or null when they cancel. The AI looks at the photo.
  final Future<OryksaImage?> Function()? onPickImage;

  /// Client with the session token.
  final OryksaClient client;

  /// `en`, `pt`, `br` or `es`.
  final String lang;

  /// Colors.
  final OryksaChatTheme theme;

  /// Open the panel on the left on wide screens.
  final bool alignLeft;

  @override
  State<OryksaChatButton> createState() => _OryksaChatButtonState();
}

class _OryksaChatButtonState extends State<OryksaChatButton> {
  OryksaAgent? _agent;

  @override
  void initState() {
    super.initState();
    widget.client.agent().then((a) {
      if (mounted) setState(() => _agent = a);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = _tx[_lang(widget.lang)]!;
    final name = _agent?.name ?? 'ORYKSA';
    return Material(
      color: widget.theme.accent,
      shape: const StadiumBorder(),
      elevation: 8,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => showOryksaChat(context,
            client: widget.client,
            lang: widget.lang,
            theme: widget.theme,
            alignLeft: widget.alignLeft,
            appContext: widget.appContext,
            voice: widget.voice, onPickImage: widget.onPickImage),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: _Avatar(url: _agent?.avatar, size: 42),
            ),
            const SizedBox(width: 10),
            Text('${t['talk']} $name'.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1)),
          ]),
        ),
      ),
    );
  }
}

/// Small copy button under a reply: copies the text and shows a check for a moment.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text, required this.label, required this.color});
  final String text;
  final String label;
  final Color color;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _done = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _done = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: _copy,
        tooltip: widget.label,
        icon: Icon(_done ? Icons.check_rounded : Icons.content_copy_rounded, size: 16, color: widget.color),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      );
}
