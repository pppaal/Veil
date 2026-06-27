#!/usr/bin/env bash
#
# Verify two Android build artifacts (.aab or .apk) contain byte-identical
# compiled code and resources, ignoring the parts that are *expected* to
# differ: the APK signing block (META-INF/*.RSA|*.SF|*.MF) and zip-container
# timestamps. We hash entry *contents*, not the zip wrapper, so timestamps
# never enter the comparison.
#
# Usage: scripts/verify-reproducible-build.sh <a.aab> <b.aab>
# Exit 0 if the normalized contents match, 1 otherwise.
#
# See docs/reproducible-builds.md.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <artifact-a.aab|.apk> <artifact-b.aab|.apk>" >&2
  exit 2
fi

A="$1"
B="$2"
for f in "$A" "$B"; do
  [ -f "$f" ] || { echo "not a file: $f" >&2; exit 2; }
done

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# Produce a sorted "relpath  sha256" manifest of an archive's content
# entries, excluding signature material.
manifest() {
  local archive="$1" out="$2" dir
  dir="$(mktemp -d)"
  unzip -qq -o "$archive" -d "$dir"
  ( cd "$dir"
    # Drop the signing block — Play App Signing re-signs, so it is not part
    # of reproducible content.
    find . -path './META-INF/*' \( -name '*.RSA' -o -name '*.SF' -o -name '*.MF' \) -delete 2>/dev/null || true
    find . -type f | LC_ALL=C sort | while IFS= read -r rel; do
      printf '%s  %s\n' "${rel#./}" "$(sha "$rel")"
    done
  ) > "$out"
  rm -rf "$dir"
}

MA="$(mktemp)"; MB="$(mktemp)"
trap 'rm -f "$MA" "$MB"' EXIT
manifest "$A" "$MA"
manifest "$B" "$MB"

if diff -u "$MA" "$MB" > /tmp/repro-diff.$$  2>&1; then
  echo "REPRODUCIBLE: normalized contents match ($(wc -l < "$MA" | tr -d ' ') entries)."
  rm -f /tmp/repro-diff.$$
  exit 0
fi

echo "NOT REPRODUCIBLE — differing entries:" >&2
# Show only the entry names that differ, not full hashes, for readability.
diff <(cut -d' ' -f1 "$MA") <(cut -d' ' -f1 "$MB") | grep -E '^[<>]' || true
echo "--- content hash differences ---" >&2
diff -u "$MA" "$MB" | grep -E '^[+-][^+-]' | head -40 || true
rm -f /tmp/repro-diff.$$
exit 1
