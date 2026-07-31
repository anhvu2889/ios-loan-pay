#!/bin/sh
# Release audit: prove two security invariants on the RELEASE product.
#   1. No StubURLProtocol symbol — the test-only MITM class never ships.
#   2. No ATS exceptions in the Release Info.plist — no cleartext, no
#      local-networking hole (that lives in Info-Debug.plist only).
#
# Usage: Scripts/release-audit.sh ["platform=iOS Simulator,id=<UDID>"]
set -eu

cd "$(dirname "$0")/.."
DEST="${1:-generic/platform=iOS Simulator}"
DERIVED="$(mktemp -d)/DerivedData"

echo "audit: building Release…"
xcodebuild -project loanpay.xcodeproj -scheme loanpay -configuration Release \
    -destination "$DEST" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO build -quiet

APP=$(find "$DERIVED/Build/Products" -name "loanpay.app" -maxdepth 2 | head -1)
BINARY="$APP/loanpay"
PLIST="$APP/Info.plist"

STATUS=0

if nm -a "$BINARY" 2>/dev/null | grep -q StubURLProtocol || strings "$BINARY" | grep -q StubURLProtocol; then
    echo "audit: FAIL — StubURLProtocol symbol found in the Release binary" >&2
    STATUS=1
else
    echo "audit: OK — no StubURLProtocol in the Release binary"
fi

if plutil -p "$PLIST" | grep -q NSAppTransportSecurity; then
    echo "audit: FAIL — Release Info.plist contains ATS exceptions" >&2
    STATUS=1
else
    echo "audit: OK — Release Info.plist has no ATS exceptions"
fi

exit $STATUS
