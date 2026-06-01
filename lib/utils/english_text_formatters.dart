// English prose helpers for auto-generated profile text (title case, degrees).

const _smallWords = {
  'a', 'an', 'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'as', 'by',
};

/// Title case for multi-word labels (city, occupation, family type).
String toTitleCaseLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  return raw
      .trim()
      .split(RegExp(r'\s+'))
      .map((word) {
        final lower = word.toLowerCase();
        if (word.isEmpty) return word;
        if (_smallWords.contains(lower)) return lower;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      })
      .join(' ');
}

/// "a" vs "an" for the first word of [phrase] (heuristic for English prose).
String indefiniteArticleBeforePhrase(String phrase) {
  final t = phrase.trim().toLowerCase();
  if (t.isEmpty) return 'a';
  final first = t.split(RegExp(r'\s+')).first;
  if (first.isEmpty) return 'a';
  if ('aeiou'.contains(first[0])) return 'an';
  return 'a';
}

/// Formats education strings: "b.tech / b.e." → "B.Tech / B.E.", "mba" → "Mba"
/// (users can edit); multi-word → title case.
String formatEducationForProse(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final chunks = raw.split('/');
  return chunks.map((c) => _formatEducationChunk(c.trim())).where((s) => s.isNotEmpty).join(' / ');
}

String _formatEducationChunk(String chunk) {
  if (chunk.isEmpty) return '';
  if (chunk.contains('.')) {
    return chunk
        .split('.')
        .where((p) => p.trim().isNotEmpty)
        .map((p) {
          final w = p.trim();
          if (w.isEmpty) return '';
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        })
        .join('.');
  }
  return toTitleCaseLabel(chunk);
}

/// "guntur, andhra pradesh" → "Guntur, Andhra Pradesh"
String formatCityStateLine(String city, String? state) {
  final c = toTitleCaseLabel(city);
  if (state == null || state.trim().isEmpty) return c;
  return '$c, ${toTitleCaseLabel(state)}';
}

String formatCommaSeparatedLabels(Iterable<String> items, {int maxItems = 3}) {
  final list = items.take(maxItems).map((e) => toTitleCaseLabel(e.trim())).where((s) => s.isNotEmpty).toList();
  if (list.isEmpty) return '';
  if (list.length == 1) return list.first;
  if (list.length == 2) return '${list.first} and ${list.last}';
  return '${list.sublist(0, list.length - 1).join(', ')}, and ${list.last}';
}
