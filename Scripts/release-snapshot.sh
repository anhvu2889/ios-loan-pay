#!/bin/sh
# Snapshot a release cut: tag the SHA and record exactly what it shipped
# (commit + full feature-flag state) in a committed manifest.
#
# Usage: Scripts/release-snapshot.sh <version>   e.g. 1.4.0
set -eu

VERSION="${1:?usage: release-snapshot.sh <version>}"
cd "$(dirname "$0")/.."

SHA=$(git rev-parse HEAD)
DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FLAGS=$(cat loanpay/Resources/flags.json)

mkdir -p Releases
MANIFEST="Releases/${VERSION}-manifest.json"

# The manifest is the answer to "what exactly did <version> ship?" —
# a file in the repo, not an archaeology project.
cat > "$MANIFEST" <<EOF
{
  "version": "${VERSION}",
  "sha": "${SHA}",
  "cutAt": "${DATE}",
  "flags": ${FLAGS}
}
EOF

git add "$MANIFEST"
git commit -m "Release snapshot ${VERSION}: manifest (SHA + flag state)"
git tag -a "v${VERSION}" -m "LoanPay ${VERSION} (flags snapshot in ${MANIFEST})"

echo "snapshot: tagged v${VERSION} at ${SHA}"
echo "snapshot: manifest at ${MANIFEST}"
