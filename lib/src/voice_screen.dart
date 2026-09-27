import 'package:flutter/material.dart';

import 'chat.dart' show OryksaChatTheme;
import 'models.dart';
import 'voice.dart';

const Map<String, Map<String, String>> _vx = {
  'en': {
    'listening': "I'm listening",
    'listeningSub': 'Speak to me. You can cut me off any time.',
    'hearing': 'Go on, I am listening.',
    'thinking': 'One moment...',
    'muted': 'Paused',
    'mutedSub': 'Tap the mic to talk again.',
    'micError': 'Microphone unavailable',
    'micErrorSub': 'Allow microphone access, or close other apps using it.',
    'noisy': 'Too much background noise',
    'noisySub': 'I cannot tell your voice from the noise. Move somewhere quieter, or type to me.',
    'notUnderstood': 'I could not understand',
    'notUnderstoodSub': 'Say it again, please.',
    'tapToSend': 'Tap the picture to send what you said.',
    'mute': 'Mute',
    'unmute': 'Unmute',
    'close': 'Close',
  },
  'pt': {
    'listening': 'Estou a ouvir',
    'listeningSub': 'Fala comigo. Podes interromper-me quando quiseres.',
    'hearing': 'Continua, estou a ouvir.',
    'thinking': 'Um momento...',
    'muted': 'Em pausa',
    'mutedSub': 'Toca no microfone para voltar a falar.',
    'micError': 'Microfone indisponível',
    'micErrorSub': 'Permite o acesso ao microfone, ou fecha outras apps que o estejam a usar.',
    'noisy': 'Demasiado barulho',
    'noisySub': 'Não consigo distinguir a tua voz do barulho. Vai para um sítio mais calmo, ou escreve-me.',
    'notUnderstood': 'Não percebi',
    'notUnderstoodSub': 'Diz outra vez, por favor.',
    'tapToSend': 'Toca na imagem para enviar o que disseste.',
    'mute': 'Silenciar',
    'unmute': 'Ativar som',
    'close': 'Fechar',
  },
  'br': {
    'listening': 'Estou ouvindo',
    'listeningSub': 'Fale comigo. Você pode me interromper quando quiser.',
    'hearing': 'Continue, estou ouvindo.',
    'thinking': 'Um momento...',
    'muted': 'Em pausa',
    'mutedSub': 'Toque no microfone para voltar a falar.',
    'micError': 'Microfone indisponível',
    'micErrorSub': 'Permita o acesso ao microfone, ou feche outros apps que estejam usando.',
    'noisy': 'Barulho demais',
    'noisySub': 'Não consigo separar sua voz do barulho. Vá para um lugar mais calmo, ou digite para mim.',
    'notUnderstood': 'Não entendi',
    'notUnderstoodSub': 'Fale de novo, por favor.',
    'tapToSend': 'Toque na imagem para enviar o que você disse.',
    'mute': 'Silenciar',
    'unmute': 'Ativar som',
    'close': 'Fechar',
  },
  'es': {
    'listening': 'Te escucho',
    'listeningSub': 'Háblame. Puedes interrumpirme cuando quieras.',
    'hearing': 'Sigue, te escucho.',
    'thinking': 'Un momento...',
    'muted': 'En pausa',
    'mutedSub': 'Toca el micrófono para volver a hablar.',
    'micError': 'Micrófono no disponible',
    'micErrorSub': 'Permite el acceso al micrófono, o cierra otras apps que lo estén usando.',
    'noisy': 'Demasiado ruido',
    'noisySub': 'No distingo tu voz del ruido. Ve a un sitio más tranquilo, o escríbeme.',
    'notUnderstood': 'No te entendí',
    'notUnderstoodSub': 'Dilo otra vez, por favor.',
    'tapToSend': 'Toca la imagen para enviar lo que dijiste.',
    'mute': 'Silenciar',
    'unmute': 'Activar sonido',
    'close': 'Cerrar',
  },
};

/// Texts of the voice screen for [lang] (`en`, `pt`, `br`, `es`).
Map<String, String> oryksaVoiceTexts(String lang) => _vx[lang] ?? _vx['en']!;

/// Full-screen voice conversation, the same as the ORYKSA app: the photo of the AI
/// with a halo, "I'm listening" / her answer, Mute and Close. What is said goes to
/// the chat through [OryksaVoiceController.onUserText] and [OryksaVoiceController.onReply].
class OryksaVoiceScreen extends StatefulWidget {
  /// Creates the screen for [controller]. It starts listening when it opens and
  /// closes the microphone when it closes.
  const OryksaVoiceScreen({
    super.key,
    required this.controller,
    required this.agent,
    this.lang = 'en',
    this.theme = const OryksaChatTheme(),
  });

  /// Voice controller.
  final OryksaVoiceController controller;

  /// Name and photo of the AI.
  final OryksaAgent agent;

  /// `en`, `pt`, `br` or `es`.
  final String lang;

  /// Colors.
  final OryksaChatTheme theme;

  @override
  State<OryksaVoiceScreen> createState() => _OryksaVoiceScreenState();
}

class _OryksaVoiceScreenState extends State<OryksaVoiceScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  OryksaVoiceController get c => widget.controller;
  Map<String, String> get t => oryksaVoiceTexts(widget.lang);

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    c.start();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.close();
    _pulse.dispose();
    super.dispose();
  }

  (String, String) _texts() {
    switch (c.phase) {
      case OryksaVoicePhase.starting:
      case OryksaVoicePhase.listening:
        return (t['listening']!, t['listeningSub']!);
      case OryksaVoicePhase.hearing:
        return (t['listening']!, t['hearing']!);
      case OryksaVoicePhase.thinking:
        return (c.lastHeard.isNotEmpty ? c.lastHeard : '...', t['thinking']!);
      case OryksaVoicePhase.speaking:
        return (widget.agent.name, c.lastReply);
      case OryksaVoicePhase.muted:
        return (t['muted']!, t['mutedSub']!);
      case OryksaVoicePhase.micError:
        return (t['micError']!, t['micErrorSub']!);
      case OryksaVoicePhase.noisy:
        return (t['noisy']!, t['noisySub']!);
      case OryksaVoicePhase.notUnderstood:
        return (t['notUnderstood']!, t['notUnderstoodSub']!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.theme;
    final (title, sub) = _texts();
    final muted = c.phase == OryksaVoicePhase.muted;
    return Scaffold(
      backgroundColor: th.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [th.background, th.soft]),
        ),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
              child: Row(children: [
                _Photo(url: widget.agent.avatar, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.agent.name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: th.ink)),
                    if ((widget.agent.business ?? '').isNotEmpty)
                      Text(widget.agent.business!, style: TextStyle(fontSize: 11, color: th.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close, size: 20, color: th.muted),
                  tooltip: t['close'],
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - 200),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    GestureDetector(onTap: c.sendNow, child: _halo(th)),
                    const SizedBox(height: 14),
                    Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: th.ink)),
                    const SizedBox(height: 8),
                    Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.5, color: th.muted)),
                    const SizedBox(height: 10),
                    if (c.phase == OryksaVoicePhase.hearing)
                      Text(t['tapToSend']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: Color(0xFFAAB0CC))),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _button(muted ? Icons.mic_off_outlined : Icons.mic_none, muted ? t['unmute']! : t['mute']!, false, c.toggleMute, th),
                      const SizedBox(width: 46),
                      _button(Icons.close, t['close']!, true, () => Navigator.of(context).maybePop(), th),
                    ]),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'POWERED BY '),
                  TextSpan(text: 'ORYKSA', style: TextStyle(color: th.accent, fontWeight: FontWeight.w800)),
                ]),
                style: const TextStyle(fontSize: 10.5, letterSpacing: 1.3, color: Color(0xFF9CA3AF)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _halo(OryksaChatTheme th) => SizedBox(
        width: 250,
        height: 250,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) {
            final active = c.phase == OryksaVoicePhase.hearing || c.phase == OryksaVoicePhase.speaking;
            Widget ring(double s, double op, double delay) {
              final v = ((_pulse.value + delay) % 1.0);
              final k = active ? 1 + .07 * Curves.easeInOut.transform(v < .5 ? v * 2 : (1 - v) * 2) : 1.0;
              return Transform.scale(
                scale: k,
                child: Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: th.accent.withValues(alpha: op))),
              );
            }

            return Stack(alignment: Alignment.center, children: [ring(236, .06, 0), ring(184, .09, .125), ring(136, .13, .25), child!]);
          },
          child: _Photo(url: widget.agent.avatar, size: 124),
        ),
      );

  Widget _button(IconData ic, String label, bool cancel, VoidCallback tap, OryksaChatTheme th) => GestureDetector(
        onTap: tap,
        child: Column(children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cancel ? const Color(0xFFFDF0EF) : th.background,
              border: Border.all(color: cancel ? const Color(0xFFF3C0BE) : const Color(0xFFECECF6), width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x0F1E1E50), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Icon(ic, size: 22, color: cancel ? const Color(0xFFE05A52) : th.muted),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: cancel ? const Color(0xFFE05A52) : th.muted)),
        ]),
      );
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url, required this.size});
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEEEBFB))),
        ),
      );
}
