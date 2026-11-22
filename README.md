# rustdesk-bulk-input
Not a fork. Nightly workflow resolves the latest upstream RustDesk release, reads its toolchain versions, applies `scripts/apply.py` (adds a floating bulk-input button on the mobile remote page), runs tests/analysis/verification, signs and publishes an APK. Anchor drift upstream fails the build instead of shipping a broken patch.
Bump `PATCH_REV` after changing the overlay to force a rebuild.
