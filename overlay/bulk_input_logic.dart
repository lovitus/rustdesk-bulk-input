// Pure Dart (no Flutter deps) so it can be unit-tested in CI.

enum BulkNewlineMode { shiftEnter, enter, space }

class BulkOp {
  final bool newline;
  final String text;
  const BulkOp.text(this.text) : newline = false;
  const BulkOp.newline()
      : newline = true,
        text = '';
  @override
  bool operator ==(Object o) =>
      o is BulkOp && o.newline == newline && o.text == text;
  @override
  int get hashCode => Object.hash(newline, text);
  @override
  String toString() => newline ? 'NL' : 'T($text)';
}

/// Split [input] into text chunks and explicit newline ops. Text never
/// contains '\n', so the remote never turns it into a bare Enter.
List<BulkOp> planBulkInput(String input, {int maxChunk = 200}) {
  final lines =
      input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final ops = <BulkOp>[];
  for (var i = 0; i < lines.length; i++) {
    final s = lines[i];
    for (var j = 0; j < s.length;) {
      var end = j + maxChunk > s.length ? s.length : j + maxChunk;
      // never split a UTF-16 surrogate pair
      if (end < s.length && (s.codeUnitAt(end - 1) & 0xFC00) == 0xD800) {
        end--;
      }
      ops.add(BulkOp.text(s.substring(j, end)));
      j = end;
    }
    if (i < lines.length - 1) ops.add(const BulkOp.newline());
  }
  return ops;
}
