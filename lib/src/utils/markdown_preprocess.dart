// Markdown preprocessing for the reader.
//
// flutter_markdown does not parse HTML, so `<br>` would show up as literal
// text. GFM hard breaks (two trailing spaces + newline) DO render as line
// breaks, so we rewrite `<br>` to a hard break — except inside table rows,
// where a raw newline would break the table structure (there we substitute
// a space instead).

final RegExp _brPattern = RegExp(r'<br\s*/?>', caseSensitive: false);

String preprocessMarkdown(String data) {
  if (!data.contains(RegExp(r'<br', caseSensitive: false))) return data;
  final lines = data.split('\n');
  final out = <String>[];
  for (final line in lines) {
    out.add(line.contains('|')
        ? line.replaceAll(_brPattern, ' ')
        : line.replaceAll(_brPattern, '  \n'));
  }
  return out.join('\n');
}
