import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'bulk_input_logic.dart';

/// True while the bulk dialog is open. RustDesk's remote page watches the
/// soft keyboard and, on every change, steals focus back to its hidden input
/// field / disables the native keyboard; that races with our TextField and
/// made the keyboard collapse right after showing. The page checks this flag.
bool bulkInputActive = false;

/// Floating button + multiline dialog. Text goes through the remote key-event
/// channel (KeyEvent.seq) and never touches the system clipboard.
class BulkInputButton extends StatefulWidget {
  final FFI ffi;
  final VoidCallback onAcquireKeyboard;
  const BulkInputButton({
    Key? key,
    required this.ffi,
    required this.onAcquireKeyboard,
  }) : super(key: key);
  @override
  State<BulkInputButton> createState() => _BulkInputButtonState();
}

class _BulkInputButtonState extends State<BulkInputButton> {
  Offset? _pos;
  static String _draft = '';
  static BulkNewlineMode _mode = BulkNewlineMode.shiftEnter;
  static bool _sending = false;

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

  bool _allowed(FFI ffi) =>
      ffi.ffiModel.keyboard &&
      !ffi.inputModel.isViewOnly &&
      ffi.inputModel.keyboardInputAllowed;

  Future<void> _send(FFI ffi, ModalRoute<dynamic>? owner, String text) async {
    if (_sending || !_allowed(ffi) || owner?.isActive == false) return;
    _sending = true;
    final mode = _mode; // fixed for the whole transmission
    final sid = ffi.sessionId;
    try {
      for (final op in planBulkInput(text)) {
        if (!_allowed(ffi) || owner?.isActive == false) return;
        if (!op.newline) {
          await bind.sessionInputString(sessionId: sid, value: op.text);
          await Future.delayed(const Duration(milliseconds: 15));
          continue;
        }
        if (mode == BulkNewlineMode.space) {
          await bind.sessionInputString(sessionId: sid, value: ' ');
        } else {
          await bind.sessionInputKey(
              sessionId: sid,
              name: 'VK_RETURN',
              down: false,
              press: true,
              alt: false,
              ctrl: false,
              shift: mode == BulkNewlineMode.shiftEnter,
              command: false);
        }
        await Future.delayed(const Duration(milliseconds: 25));
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _open() async {
    if (bulkInputActive) return;
    final ffi = widget.ffi;
    final owner = ModalRoute.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    // View.of: the Scaffold body's MediaQuery has the keyboard inset removed.
    final kbWasVisible = View.of(context).viewInsets.bottom > 0;
    final c = TextEditingController(text: _draft);
    void saveDraft() => _draft = c.text;
    c.addListener(saveDraft);
    final focus = FocusNode();
    var generation = 0;
    String? error;
    var initialShowScheduled = false;
    late final DialogRoute<void> route;

    Future<void> showKeyboard() async {
      if (!route.isCurrent) return;
      final request = ++generation;
      await ffi.invokeMethod('enable_soft_keyboard', true);
      if (request != generation || !route.isCurrent) return;
      // EditableText opens/shows its own text-input connection (focus + IME).
      final st = focus.context?.findAncestorStateOfType<EditableTextState>();
      if (st != null) {
        st.requestKeyboard();
      } else {
        focus.requestFocus();
      }
    }

    route = DialogRoute<void>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        if (!initialShowScheduled) {
          initialShowScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => showKeyboard());
        }
        return AlertDialog(
          title: const Text('Bulk input'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: c,
                focusNode: focus,
                minLines: 6,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(error!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 4),
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.keyboard),
                  tooltip: 'Show keyboard',
                  onPressed: showKeyboard,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_hide),
                  tooltip: 'Hide keyboard',
                  onPressed: () {
                    ++generation; // cancel any pending show
                    focus.unfocus();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: DropdownButton<BulkNewlineMode>(
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
                )),
              ]),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
            TextButton(onPressed: () => c.clear(), child: const Text('Clear')),
            ElevatedButton(
                onPressed: () {
                  // reject BEFORE touching the draft, so nothing is lost
                  if (_sending) {
                    setS(() => error = 'Previous send still running');
                    return;
                  }
                  if (!_allowed(ffi) || owner?.isActive == false) {
                    setS(() => error = 'Keyboard input not allowed');
                    return;
                  }
                  final t = c.text;
                  c.removeListener(saveDraft);
                  _draft = '';
                  Navigator.pop(ctx);
                  _send(ffi, owner, t);
                },
                child: const Text('Send')),
          ],
        );
      }),
    );

    bulkInputActive = true;
    try {
      // cancel upstream timers that would re-take focus / hide the keyboard
      widget.onAcquireKeyboard();
      navigator.push<void>(route); // its future may never complete on forced removal
      // controller/focus node are still used by the exit animation until now
      await route.completed;
    } finally {
      ++generation;
      c.dispose();
      focus.dispose();
      bulkInputActive = false;
      if (!kbWasVisible && owner?.isActive == true) {
        ffi.invokeMethod('enable_soft_keyboard', false);
      }
    }
  }
}
