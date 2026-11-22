import 'package:test/test.dart';
import 'bulk_input_logic.dart';

void main() {
  test('newlines become explicit ops, never inside text', () {
    final ops = planBulkInput('a\r\nb\n\nc');
    expect(ops, [
      const BulkOp.text('a'),
      const BulkOp.newline(),
      const BulkOp.text('b'),
      const BulkOp.newline(),
      const BulkOp.newline(),
      const BulkOp.text('c'),
    ]);
  });
  test('chunking keeps surrogate pairs', () {
    final s = '😀' * 150;
    final ops = planBulkInput(s, maxChunk: 201);
    expect(ops.map((o) => o.text).join(), s);
    for (final o in ops) {
      expect(o.text.codeUnitAt(o.text.length - 1) & 0xFC00, isNot(0xD800));
    }
  });
  test('maxChunk < 2 rejected', () {
    expect(() => planBulkInput('😀', maxChunk: 1), throwsRangeError);
  });
  test('empty input', () => expect(planBulkInput(''), isEmpty));
}
