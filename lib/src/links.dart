import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'client.dart';
import 'models.dart';

/// What your app does with a link the AI gave (a product, a service, a page). Return
/// true when your app opened it itself (for example its own product screen); return
/// false and the SDK opens it in the browser (or the app that owns the address).
typedef OryksaLinkHandler = bool Function(Uri link);

final RegExp _url = RegExp(r'''https?://[^\s<>"'\)\]]+''', caseSensitive: false);
final RegExp _mail = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');

String _trimEnd(String u) => u.replaceAll(RegExp(r'[.,;:!?…]+$'), '');

/// The distinct web links of [text], in order (at most [max]).
List<String> oryksaLinksIn(String text, {int max = 3}) {
  final out = <String>[];
  for (final m in _url.allMatches(text)) {
    final u = _trimEnd(m.group(0)!);
    if (!out.contains(u)) out.add(u);
    if (out.length >= max) break;
  }
  return out;
}

/// [text] without its web links (for the voice screen: the link is on the button).
String oryksaWithoutLinks(String text) => text
    .replaceAll(_url, '')
    .replaceAll(RegExp(r'[ \t]+\n'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAll(RegExp(r'\s+([.,;!?])'), r'$1')
    .replaceAll(RegExp(r':\s*$', multiLine: true), '')
    .trim();

/// Opens [link]: your [handler] first, then the browser or the app that owns the address.
Future<void> oryksaOpenLink(Uri link, OryksaLinkHandler? handler) async {
  if (handler != null && handler(link)) return;
  try {
    if (!await launchUrl(link, mode: LaunchMode.externalApplication)) {
      await launchUrl(link);
    }
  } catch (_) {}
}

/// Text of a message with **bold** parts and links (web and e-mail) the customer can tap.
class OryksaRichText extends StatefulWidget {
  /// Creates the text.
  const OryksaRichText(this.text, {super.key, required this.style, required this.linkColor, this.onLink});

  /// The message.
  final String text;

  /// Style of the text.
  final TextStyle style;

  /// Color of the links.
  final Color linkColor;

  /// Your handler for the links (see [OryksaLinkHandler]).
  final OryksaLinkHandler? onLink;

  @override
  State<OryksaRichText> createState() => _OryksaRichTextState();
}

class _OryksaRichTextState extends State<OryksaRichText> {
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    for (final r in _taps) {
      r.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _spans() {
    for (final r in _taps) {
      r.dispose();
    }
    _taps.clear();
    final out = <InlineSpan>[];
    final parts = widget.text.split('**');
    if (parts.length < 3) {
      _links(widget.text, widget.style, out);
      return out;
    }
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      _links(parts[i], i.isOdd ? widget.style.copyWith(fontWeight: FontWeight.w700) : widget.style, out);
    }
    return out;
  }

  void _links(String s, TextStyle base, List<InlineSpan> out) {
    final hits = <(int, int, Uri)>[];
    for (final m in _url.allMatches(s)) {
      final u = _trimEnd(m.group(0)!);
      final uri = Uri.tryParse(u);
      if (uri != null) hits.add((m.start, m.start + u.length, uri));
    }
    for (final m in _mail.allMatches(s)) {
      if (hits.any((h) => m.start < h.$2 && m.end > h.$1)) continue;
      hits.add((m.start, m.end, Uri(scheme: 'mailto', path: m.group(0))));
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    var at = 0;
    for (final h in hits) {
      if (h.$1 < at) continue;
      if (h.$1 > at) out.add(TextSpan(text: s.substring(at, h.$1), style: base));
      final tap = TapGestureRecognizer()..onTap = () => oryksaOpenLink(h.$3, widget.onLink);
      _taps.add(tap);
      out.add(TextSpan(
        text: s.substring(h.$1, h.$2),
        style: base.copyWith(color: widget.linkColor, decoration: TextDecoration.underline, decorationColor: widget.linkColor),
        recognizer: tap,
        mouseCursor: SystemMouseCursors.click,
      ));
      at = h.$2;
    }
    if (at < s.length) out.add(TextSpan(text: s.substring(at), style: base));
  }

  @override
  Widget build(BuildContext context) => SelectableText.rich(TextSpan(children: _spans()));
}

/// The card under a reply for a link of the business's own site: its picture, its title
/// and an Open button. Links of other sites show the address and the button.
class OryksaLinkCard extends StatefulWidget {
  /// Creates the card.
  const OryksaLinkCard({
    super.key,
    required this.url,
    required this.client,
    required this.openLabel,
    this.onLink,
    this.accent = const Color(0xFF5B47E0),
    this.ink = const Color(0xFF1F2937),
    this.muted = const Color(0xFF6B7280),
    this.background = Colors.white,
    this.line = const Color(0xFFE5E7EB),
    this.onOpened,
  });

  /// The link.
  final String url;

  /// Client (reads the title and picture from ORYKSA).
  final OryksaClient client;

  /// Text of the button (for example "Abrir").
  final String openLabel;

  /// Your handler for the links (see [OryksaLinkHandler]).
  final OryksaLinkHandler? onLink;

  /// Called after the link opened (the voice screen closes itself).
  final VoidCallback? onOpened;

  /// Colors.
  final Color accent, ink, muted, background, line;

  @override
  State<OryksaLinkCard> createState() => _OryksaLinkCardState();
}

class _OryksaLinkCardState extends State<OryksaLinkCard> {
  OryksaLinkPreview? _p;

  @override
  void initState() {
    super.initState();
    widget.client.linkPreview(widget.url).then((p) {
      if (mounted && p != null) setState(() => _p = p);
    });
  }

  Future<void> _open() async {
    final u = Uri.tryParse(widget.url);
    if (u == null) return;
    widget.onOpened?.call();
    await oryksaOpenLink(u, widget.onLink);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final host = Uri.tryParse(widget.url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '';
    final title = (p?.title ?? '').isNotEmpty ? p!.title : host;
    final sub = (p?.price ?? '').isNotEmpty ? '${p!.price} · ${p.site}' : ((p?.site ?? '').isNotEmpty ? p!.site : host);
    final img = p?.image ?? '';
    return Semantics(
      button: true,
      label: '${widget.openLabel}: $title',
      child: Material(
        color: widget.background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _open,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: widget.line)),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: img.isEmpty
                      ? ColoredBox(color: widget.line, child: Icon(Icons.link_rounded, color: widget.muted))
                      : Image.network(img, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(color: widget.line, child: Icon(Icons.link_rounded, color: widget.muted))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w700, color: widget.ink)),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: widget.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _open,
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 36),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                child: Text(widget.openLabel),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
