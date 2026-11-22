#!/usr/bin/env python3
"""Apply the bulk-input patch to an upstream RustDesk checkout.
Idempotent; exits non-zero if upstream anchors drifted."""
import re, shutil, sys, pathlib

up = pathlib.Path(sys.argv[1])
here = pathlib.Path(__file__).resolve().parent.parent / 'overlay'
w = up / 'flutter/lib/mobile/widgets'
for f in ('bulk_input.dart', 'bulk_input_logic.dart'):
    shutil.copy(here / f, w / f)

# the Rust side must still expose the APIs we call
ffi = (up / 'src/flutter_ffi.rs').read_text()
for fn in ('pub fn session_input_string', 'pub fn session_input_key'):
    if fn not in ffi:
        sys.exit('ANCHOR DRIFT: missing ' + fn)

p = up / 'flutter/lib/mobile/pages/remote_page.dart'
s = p.read_text()
if 'BulkInputButton' in s:
    print('already patched')
    sys.exit(0)
m = re.search(r"^import 'package:flutter/material\.dart';\n", s, re.M)
if not m:
    sys.exit('ANCHOR DRIFT: material import')
s = s[:m.end()] + "import 'package:flutter_hbb/mobile/widgets/bulk_input.dart';\n" + s[m.end():]
i = s.find('Widget getBodyForMobile()')
if i < 0:
    sys.exit('ANCHOR DRIFT: getBodyForMobile')
m = re.compile(r'^([ \t]*)if \(gFFI\.ffiModel\.touchMode\) \{', re.M).search(s, i)
if not m:
    sys.exit('ANCHOR DRIFT: touchMode block')
ind = m.group(1)
ins = (f"{ind}if (gFFI.ffiModel.keyboard) {{\n"
       f"{ind}  paints.add(BulkInputButton(ffi: gFFI));\n{ind}}}\n")
s = s[:m.start()] + ins + s[m.start():]
p.write_text(s)
print('patched')
