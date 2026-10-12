#!/usr/bin/env bash
# Download the third-party binaries bundled in this repo (needs internet; run on a dev machine).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VER="${COMPOSE_VERSION:-v2.29.7}"
mkdir -p "$HERE/bin"
curl -fL -o "$HERE/bin/docker-compose" "https://github.com/docker/compose/releases/download/${VER}/docker-compose-linux-x86_64"
chmod +x "$HERE/bin/docker-compose"
ls -l "$HERE/bin/docker-compose"
echo "Commit bin/docker-compose to the repo so servers get it with git clone."
