import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'bulk_input_logic.dart';

/// Floating button + multiline dialog. Text goes through the remote key-event
/// channel (KeyEvent.seq) and never touches the system clipboard.
class BulkInputButton extends StatefulWidget {
  final FFI ffi;
  const BulkInputButton({Key? key, required this.ffi}) : super(key: key);
  @override
  State<BulkInputButton> createState() => _BulkInputButtonState();
}

class _BulkInputButtonState extends State<BulkInputButton> {
  Offset? _pos;
  static String _draft = '';
  static BulkNewlineMode _mode = BulkNewlineMode.shiftEnter;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final p = _pos ?? Offset(size.width - 64, size.height * 0.4);
    return Positioned(
      left: p.dx,
      top: p.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = Offset(
            (p.dx + d.delta.dx).clamp(0.0, size.width - 48),
            (p.dy + d.delta.dy).clamp(0.0, size.height - 48))),
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.white),
            tooltip: 'Bulk input',
            onPressed: _open,
          ),
        ),
      ),
    );
  }

  Future<void> _send(String text) async {
    final sid = widget.ffi.sessionId;
    for (final op in planBulkInput(text)) {
      if (!op.newline) {
        await bind.sessionInputString(sessionId: sid, value: op.text);
        await Future.delayed(const Duration(milliseconds: 15));
        continue;
      }
      if (_mode == BulkNewlineMode.space) {
        await bind.sessionInputString(sessionId: sid, value: ' ');
      } else {
        await bind.sessionInputKey(
            sessionId: sid,
            name: 'VK_RETURN',
            down: false,
            press: true,
            alt: false,
            ctrl: false,
            shift: _mode == BulkNewlineMode.shiftEnter,
            command: false);
      }
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }

  void _open() {
    final c = TextEditingController(text: _draft);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Bulk input'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: c,
                autofocus: true,
                minLines: 6,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              DropdownButton<BulkNewlineMode>(
                isExpanded: true,
                value: _mode,
                items: const [
                  DropdownMenuItem(
                      value: BulkNewlineMode.shiftEnter,
                      child: Text('Newline = Shift+Enter (safe)')),
                  DropdownMenuItem(
                      value: BulkNewlineMode.enter,
                      child: Text('Newline = Enter (may execute)')),
                  DropdownMenuItem(
                      value: BulkNewlineMode.space,
                      child: Text('Newline = space')),
                ],
                onChanged: (v) => setS(() => _mode = v ?? _mode),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () {
                  _draft = c.text;
                  Navigator.pop(ctx);
                },
                child: const Text('Close')),
            TextButton(onPressed: () => c.clear(), child: const Text('Clear')),
            ElevatedButton(
                onPressed: () async {
                  final t = c.text;
                  _draft = '';
                  Navigator.pop(ctx);
                  await _send(t);
                },
                child: const Text('Send')),
          ],
        );
      }),
    );
  }
}
