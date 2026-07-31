#!/bin/sh
# Secret scan: fails the build if credential-shaped strings land in the
# repo. Deliberately simple grep patterns — this is a tripwire, not a
# replacement for real secret management. Wired into CI; run locally with:
#   Scripts/secret-scan.sh
set -eu

cd "$(dirname "$0")/.."

# What we look for:
#  - api key / secret / password ASSIGNED a long literal value
#  - token= followed by a long literal
#  - PEM private key headers
#  - well-known credential prefixes (AWS, Google, GitHub, Slack, Stripe)
PATTERNS='(api[_-]?key|secret|password)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_\-]{12,}
token[[:space:]]*=[[:space:]]*["'"'"'][A-Za-z0-9._\-]{16,}
-----BEGIN[[:space:]].*PRIVATE[[:space:]]KEY
AKIA[0-9A-Z]{16}
AIza[0-9A-Za-z_\-]{35}
ghp_[A-Za-z0-9]{36}
xox[baprs]-[A-Za-z0-9\-]{10,}
sk_live_[A-Za-z0-9]{16,}'

# Scanned: tracked text files. Excluded: this script (it IS the patterns)
# and lockfiles/binaries git already marks.
FAILED=0
echo "$PATTERNS" | while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    if git grep -I -n -E -i "$pattern" -- \
        ':!Scripts/secret-scan.sh' \
        ':!*.png' ':!*.jpg' \
        2>/dev/null; then
        echo "secret-scan: pattern matched: $pattern" >&2
        FAILED=1
    fi
done

# The subshell above can't propagate FAILED; re-run cheaply for the verdict.
if echo "$PATTERNS" | { STATUS=0
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if git grep -I -q -E -i "$pattern" -- \
            ':!Scripts/secret-scan.sh' \
            ':!*.png' ':!*.jpg' \
            2>/dev/null; then
            STATUS=1
        fi
    done
    exit $STATUS
}; then
    echo "secret-scan: clean"
    exit 0
else
    echo "secret-scan: FAILED — remove the credential above and rotate it (it is already burned)." >&2
    exit 1
fi
