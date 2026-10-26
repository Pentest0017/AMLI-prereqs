#!/usr/bin/env bash
# One-click install from GitHub (server only needs access to github.com).
#
#   git clone https://github.com/Pentest0017/AMLI-prereqs.git
#   cd AMLI-prereqs && bash install.sh
#
# Does: prerequisites + images (bundled in this repo) -> clones the app repo next to this one -> deploys.
# The SQL Server image cannot be hosted on GitHub (Microsoft licence): copy mssql.tar.gz to ~ once,
# or use an existing SQL Server:  AMLI_DB_MODE=external AMLI_DB_PASSWORD='...' bash install.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_REPO="${AMLI_APP_REPO:-https://github.com/Pentest0017/AMLI-app.git}"
APP_DIR="$(dirname "$HERE")/AMLI-app"

bash "$HERE/install-prereqs.sh"
[ -f /etc/profile.d/amli-podman.sh ] && . /etc/profile.d/amli-podman.sh || true

if [ -d "$APP_DIR/.git" ]; then git -C "$APP_DIR" pull --ff-only; else git clone "$APP_REPO" "$APP_DIR"; fi
cd "$APP_DIR" && bash deploy.sh
