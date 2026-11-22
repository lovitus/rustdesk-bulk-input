#!/usr/bin/env python3
"""Apply the bulk-input patch to an upstream RustDesk checkout.
Every step is anchored and idempotent; exits non-zero on upstream drift."""
import re, shutil, sys, pathlib

up = pathlib.Path(sys.argv[1])
here = pathlib.Path(__file__).resolve().parent.parent / 'overlay'
w = up / 'flutter/lib/mobile/widgets'
for f in ('bulk_input.dart', 'bulk_input_logic.dart'):
    shutil.copy(here / f, w / f)

ffi = (up / 'src/flutter_ffi.rs').read_text()
for fn in ('pub fn session_input_string', 'pub fn session_input_key'):
    if fn not in ffi:
        sys.exit('ANCHOR DRIFT: missing ' + fn)

p = up / 'flutter/lib/mobile/pages/remote_page.dart'
s = p.read_text()

def once(old, new, what):
    global s
    if s.count(old) != 1:
        sys.exit('ANCHOR DRIFT: ' + what)
    s = s.replace(old, new, 1)

IMP = "import 'package:flutter_hbb/mobile/widgets/bulk_input.dart';\n"
if IMP not in s:
    once("import 'package:flutter/material.dart';\n",
         "import 'package:flutter/material.dart';\n" + IMP, 'material import')

# floating button
if 'BulkInputButton(' not in s:
    i = s.find('Widget getBodyForMobile()')
    if i < 0:
        sys.exit('ANCHOR DRIFT: getBodyForMobile')
    m = re.compile(r'^([ \t]*)if \(gFFI\.ffiModel\.touchMode\) \{', re.M).search(s, i)
    if not m:
        sys.exit('ANCHOR DRIFT: touchMode block')
    ind = m.group(1)
    ins = (f"{ind}if (gFFI.ffiModel.keyboard) {{\n"
           f"{ind}  paints.add(BulkInputButton(\n"
           f"{ind}    ffi: gFFI,\n"
           f"{ind}    onAcquireKeyboard: () {{\n"
           f"{ind}      _timer?.cancel();\n"
           f"{ind}      _iosKeyboardWorkaroundTimer?.cancel();\n"
           f"{ind}    }},\n"
           f"{ind}  ));\n"
           f"{ind}}}\n")
    s = s[:m.start()] + ins + s[m.start():]

# keyboard-ownership guards
G = '/*bulk*/'
def guard(sig, line):
    global s
    if G in s.split(sig, 1)[-1][:120]:
        return
    once(sig + '\n', sig + '\n' + line + ' ' + G + '\n', sig)

guard('  void onSoftKeyboardChanged(bool visible) {', '    if (!mounted || bulkInputActive) return;')
guard('  void _openKeyboardUnlocked() {', '    if (!mounted || bulkInputActive) return;')
guard('void _disableAndroidSoftKeyboard({bool? isKeyboardVisible}) {', '  if (bulkInputActive) return;')

gate = ('    // Ensure soft keyboard is not active before user confirms.\n'
        '    _showEdit = false;\n')
if gate + '    if (bulkInputActive) {' not in s:
    once(gate, gate + '    if (bulkInputActive) {\n      setState(() {});\n      return;\n    }\n',
         'wayland gate')

p.write_text(s)
print('patched')
