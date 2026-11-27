/// Splits [text] into pieces of at most [max] characters for the voice, at the end of a
/// sentence when possible, then at a comma, then at a space.
List<String> oryksaTvSplitForSpeech(String text, int max) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return const [];
  if (t.length <= max) return [t];
  final out = <String>[];
  var cur = '';
  for (final s in oryksaTvSentences(t)) {
    for (final piece in _cut(s, max)) {
      if (cur.isEmpty) {
        cur = piece;
      } else if (cur.length + 1 + piece.length <= max) {
        cur = '$cur $piece';
      } else {
        out.add(cur);
        cur = piece;
      }
    }
  }
  if (cur.isNotEmpty) out.add(cur);
  return out;
}

/// The sentences of [text] (ends at `.`, `!`, `?`, `…`, keeping the mark).
List<String> oryksaTvSentences(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return const [];
  return t
      .split(RegExp(r'(?<=[.!?…])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// The subtitle lines of [text]: one sentence per line, sentences longer than [max]
/// characters cut at a comma or a space.
List<String> oryksaTvSubtitleLines(String text, {int max = 90}) => [
      for (final s in oryksaTvSentences(text)) ..._cut(s, max),
    ];

List<String> _cut(String s, int max) {
  if (s.length <= max) return [s];
  final out = <String>[];
  var rest = s;
  while (rest.length > max) {
    var at = rest.lastIndexOf(', ', max);
    if (at > max ~/ 3) {
      at += 1; // keep the comma on the first piece
    } else {
      at = rest.lastIndexOf(' ', max);
      if (at <= 0) at = max;
    }
    out.add(rest.substring(0, at).trim());
    rest = rest.substring(at).trim();
  }
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

/// How long a subtitle stays on screen when there is no voice: about 14 characters per
/// second, never under 1.8 s.
Duration oryksaTvReadingTime(String line) {
  final ms = (line.length / 14 * 1000).round();
  return Duration(milliseconds: ms < 1800 ? 1800 : ms);
}
