#!/usr/bin/env bash
# Download pre-packed container images from a GitHub Release and load them into Podman/Docker.
# Use this when the server can reach GitHub but not Docker Hub / PyPI / npm.
#
#   ./load-images.sh <owner>/<repo> <release-tag>      # download from GitHub, verify, load
#   ./load-images.sh --local <dir>                     # load parts already copied to <dir>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

if   command -v podman >/dev/null 2>&1; then ENGINE=podman
elif command -v docker >/dev/null 2>&1; then ENGINE=docker
else fail "No podman/docker found. Run install-prereqs.sh first."; fi

if [ "${1:-}" = "--local" ]; then
  DIR="${2:?usage: $0 --local <dir>}"
else
  REPO="${1:?usage: $0 <owner>/<repo> <release-tag>}"; TAG="${2:?usage: $0 <owner>/<repo> <release-tag>}"
  DIR="${AMLI_IMAGES_DIR:-$HERE/images/$TAG}"; mkdir -p "$DIR"
  BASE="https://github.com/${REPO}/releases/download/${TAG}"
  echo "Downloading checksums from $BASE"
  curl -fsSL -o "$DIR/SHA256SUMS" "$BASE/SHA256SUMS" || fail "Cannot fetch $BASE/SHA256SUMS (wrong repo/tag, or release not published?)"
  while read -r _ name; do
    name="${name#\*}"
    echo "Downloading $name"
    curl -fL -C - --retry 5 --retry-delay 5 -o "$DIR/$name" "$BASE/$name"
  done < "$DIR/SHA256SUMS"
fi

echo "Verifying checksums"
if ! ( cd "$DIR" && sha256sum -c SHA256SUMS --quiet ); then
  # Damaged or truncated parts: re-download just those from GitHub, then verify again
  RAW="https://github.com/${AMLI_IMAGES_REPO:-Pentest0017/AMLI-prereqs}/raw/main/${DIR#"$HERE"/}"
  for attempt in 1 2 3; do
    bad=$(cd "$DIR" && sha256sum -c SHA256SUMS 2>/dev/null | awk -F: '/FAILED/ {print $1}')
    [ -z "$bad" ] && break
    for f in $bad; do
      echo "Repairing $f (attempt $attempt)"
      rm -f "$DIR/$f"
      curl -fL --retry 10 --retry-delay 5 -C - -o "$DIR/$f" "$RAW/$f" || true
    done
  done
  ( cd "$DIR" && sha256sum -c SHA256SUMS --quiet ) || fail "Checksum still wrong after re-download - the network is altering the files. Copy $DIR from your PC by USB/scp."
fi

echo "Loading images into $ENGINE (this takes a few minutes)"
parts=$(ls "$DIR"/*.part-* 2>/dev/null | sort) || true
[ -n "$parts" ] || fail "No *.part-* files in $DIR"
# shellcheck disable=SC2086
cat $parts | gzip -dc | $ENGINE load
echo "Loaded. Images now present:"
$ENGINE images --format '  {{.Repository}}:{{.Tag}}  {{.Size}}'
