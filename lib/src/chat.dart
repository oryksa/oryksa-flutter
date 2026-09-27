import 'package:flutter/material.dart';

import 'client.dart';
import 'models.dart';
import 'profanity.dart';
import 'voice.dart';
import 'voice_screen.dart';

/// Colors of the chat. The defaults are the ORYKSA website chat colors.
class OryksaChatTheme {
  /// Creates a theme.
  const OryksaChatTheme({
    this.accent = const Color(0xFF5B57E0),
    this.ink = const Color(0xFF161B3D),
    this.soft = const Color(0xFFEEEBFB),
    this.background = Colors.white,
    this.muted = const Color(0xFF6B7280),
  });

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
}

const Map<String, Map<String, String>> _tx = {
  'en': {'talk': 'Talk to', 'ph': 'Type your question', 'send': 'Send', 'err': 'Sorry, something went wrong. Try again.', 'voice': 'Talk by voice'},
  'pt': {'talk': 'Falar com', 'ph': 'Escreve a tua pergunta', 'send': 'Enviar', 'err': 'Desculpa, algo correu mal. Tenta de novo.', 'voice': 'Falar por voz'},
  'br': {'talk': 'Falar com', 'ph': 'Digite sua pergunta', 'send': 'Enviar', 'err': 'Desculpe, algo deu errado. Tente de novo.', 'voice': 'Falar por voz'},
  'es': {'talk': 'Hablar con', 'ph': 'Escribe tu pregunta', 'send': 'Enviar', 'err': 'Lo siento, algo salió mal. Inténtalo de nuevo.', 'voice': 'Hablar por voz'},
};

String _lang(String l) => _tx.containsKey(l) ? l : 'en';

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
  });

  /// Client with the session token.
  final OryksaClient client;

  /// Where the customer is in your app right now (for example the product on
  /// screen). Sent with each message so the AI answers about it.
  final OryksaAppContext? Function()? appContext;

  /// Shows the microphone button (voice conversation) when the plan has voice.
  /// Needs the microphone permission in the app (see the README).
  final bool voice;

  /// `en`, `pt`, `br` or `es`.
  final String lang;

  /// Colors.
  final OryksaChatTheme theme;

  /// Shows a close button that calls this.
  final VoidCallback? onClose;

  @override
  State<OryksaChat> createState() => _OryksaChatState();
}

class _Msg {
  _Msg(this.role, this.text);
  final String role; // user | assistant | typing
  final String text;
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

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _sug = [];
      _msgs.add(_Msg('user', text));
      _msgs.add(_Msg('typing', '...'));
      _input.clear();
    });
    _toEnd();
    String? reply;
    try {
      reply = await widget.client.sendAndWait(text, appContext: widget.appContext?.call());
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
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFECEEF6)))),
          child: Row(children: [
            _Avatar(url: a?.avatar, size: 46),
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
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _msgs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final m = _msgs[i];
              final mine = m.role == 'user';
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .72),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: mine ? th.accent : th.soft,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(mine ? 16 : 6),
                        bottomRight: Radius.circular(mine ? 6 : 16),
                      ),
                    ),
                    child: Opacity(
                      opacity: m.role == 'typing' ? .6 : 1,
                      child: SelectableText.rich(
                        TextSpan(
                            children: oryksaBold(mine ? OryksaProfanity.mask(m.text, _lang(widget.lang)) : m.text,
                                TextStyle(fontSize: 14, height: 1.5, color: mine ? Colors.white : th.ink))),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
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
                    side: const BorderSide(color: Color(0xFFDCDCF5)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                  child: Text(s),
                ),
            ]),
          ),
        Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFECEEF6)))),
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
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
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
  const _Avatar({required this.url, required this.size});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? const ColoredBox(color: Color(0xFFEEEBFB))
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEEEBFB))),
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
          child: OryksaChat(client: client, lang: lang, theme: theme, appContext: appContext, voice: voice, onClose: () => Navigator.of(ctx).pop()),
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
            child: OryksaChat(client: client, lang: lang, theme: theme, appContext: appContext, voice: voice, onClose: () => Navigator.of(ctx).pop()),
          ),
        ),
      ),
    ),
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
  });

  /// Where the customer is in your app right now (sent with each message).
  final OryksaAppContext? Function()? appContext;

  /// Shows the microphone in the chat when the plan has voice.
  final bool voice;

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
            voice: widget.voice),
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
