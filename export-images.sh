#!/usr/bin/env bash
# Pack container images into <=1.9 GB parts (GitHub Release assets are limited to 2 GB each).
# Run on a machine that HAS the images (Docker Desktop / podman) and has internet.
#
#   ./export-images.sh images-base.txt out/base      # base images (SQL Server, qdrant, caddy, mailhog)
#   ./export-images.sh images-app.txt  out/app       # AMLI backend + frontend images
#
# Then publish (needs a GitHub login):
#   gh release create images-base-v1 out/base/* --title "AMLI base images" --notes "container images"
set -euo pipefail
LIST="${1:?usage: $0 <images-file> <out-dir>}"; OUT="${2:?usage: $0 <images-file> <out-dir>}"
export MSYS_NO_PATHCONV=1
if   command -v docker >/dev/null 2>&1; then ENGINE=docker
elif command -v podman >/dev/null 2>&1; then ENGINE=podman
else echo "no docker/podman" >&2; exit 1; fi

mkdir -p "$OUT"; rm -f "$OUT"/*.part-* "$OUT"/SHA256SUMS

# Lines look like:  <local-name-or-id>  <final-tag>   (final tag is what compose expects)
imgs=()
while read -r src dst; do
  case "$src" in ''|\#*) continue;; esac
  dst="${dst:-$src}"
  $ENGINE image inspect "$src" >/dev/null 2>&1 || { echo "Missing image: $src (pull/build it first)" >&2; exit 1; }
  [ "$src" = "$dst" ] || $ENGINE tag "$src" "$dst"
  imgs+=("$dst")
done < "$LIST"

echo "Saving: ${imgs[*]}"
$ENGINE save "${imgs[@]}" | gzip -6 | split -b 1900m -d -a 2 - "$OUT/amli-images.tar.gz.part-"
( cd "$OUT" && sha256sum amli-images.tar.gz.part-* > SHA256SUMS && ls -l && cat SHA256SUMS )
echo
echo "Next: gh release create <tag> $OUT/* --title '...' --notes '...'"
