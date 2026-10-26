#!/usr/bin/env bash
# AMLI prerequisites installer - run ONCE on the Linux server, BEFORE cloning/running the app repo.
#
#   git clone https://github.com/<you>/AMLI-prereqs.git && cd AMLI-prereqs
#   bash install-prereqs.sh
#
# What it does:
#   1. checks the server (Linux, x86_64, sudo, RAM, disk)
#   2. makes sure a container engine exists (Podman or Docker): uses what is there,
#      otherwise installs it (from ./rpms offline packages if present, else dnf/yum/apt)
#   3. installs the bundled docker-compose binary (./bin/docker-compose)
#   4. wires Podman up for compose (user socket, linger, environment file)
#   5. opens firewall port 8443/tcp
#   6. optionally loads pre-packed container images from a GitHub Release (see load-images.sh)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

SUDO=""
if [ "$(id -u)" != 0 ]; then
  command -v sudo >/dev/null 2>&1 || fail "Run as root, or install sudo."
  SUDO="sudo"
fi

say "1/6 Checking the server"
[ "$(uname -s)" = "Linux" ]   || fail "Linux only."
[ "$(uname -m)" = "x86_64" ]  || fail "This bundle is for x86_64 (found $(uname -m))."
. /etc/os-release 2>/dev/null || true
echo "OS: ${PRETTY_NAME:-unknown}   user: $(id -un) (uid $(id -u))"
mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
disk_gb=$(df -P / | awk 'NR==2 {printf "%d", $4/1048576}')
echo "RAM: ${mem_gb} GB   free disk on /: ${disk_gb} GB"
[ "$mem_gb"  -ge 4 ]  || warn "Less than 4 GB RAM: SQL Server in a container needs ~2 GB for itself."
[ "$disk_gb" -ge 25 ] || warn "Less than 25 GB free disk: images need ~12 GB when unpacked."

say "2/6 Container engine"
ENGINE=""
if   command -v podman >/dev/null 2>&1; then ENGINE=podman
elif command -v docker >/dev/null 2>&1; then ENGINE=docker; fi
if [ -n "$ENGINE" ]; then
  echo "Found: $($ENGINE --version)"
else
  echo "No container engine found - installing Podman."
  if ls "$HERE"/rpms/*.rpm >/dev/null 2>&1; then
    echo "Using offline packages from ./rpms"
    $SUDO dnf install -y --disablerepo='*' "$HERE"/rpms/*.rpm 2>/dev/null || $SUDO rpm -Uvh --replacepkgs "$HERE"/rpms/*.rpm
  elif ls "$HERE"/debs/*.deb >/dev/null 2>&1; then
    echo "Using offline packages from ./debs"
    $SUDO dpkg -i "$HERE"/debs/*.deb
  elif command -v dnf >/dev/null 2>&1;     then $SUDO dnf install -y podman
  elif command -v yum >/dev/null 2>&1;     then $SUDO yum install -y podman
  elif command -v apt-get >/dev/null 2>&1; then $SUDO apt-get update && $SUDO apt-get install -y podman
  else fail "Cannot install Podman automatically. Put the Podman .rpm files in ./rpms and re-run."; fi
  command -v podman >/dev/null 2>&1 || fail "Podman installation failed."
  ENGINE=podman
fi

say "3/6 Compose tool"
[ -f "$HERE/bin/docker-compose" ] || fail "bin/docker-compose is missing from this repo (run ./fetch-binaries.sh on a machine with internet and commit it)."
$SUDO install -m 0755 "$HERE/bin/docker-compose" /usr/local/bin/docker-compose
/usr/local/bin/docker-compose version

IS_PODMAN=0; $ENGINE --version 2>&1 | grep -qi podman && IS_PODMAN=1
if [ "$IS_PODMAN" = 1 ]; then
  say "4/6 Wiring Podman for compose"
  if [ "$(id -u)" = 0 ]; then
    systemctl enable --now podman.socket
    SOCK="/run/podman/podman.sock"
  else
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    systemctl --user enable --now podman.socket || warn "Could not start the user podman.socket (is a login session/linger available?)"
    $SUDO loginctl enable-linger "$(id -un)" || warn "Could not enable linger (containers may stop when you log out)."
    SOCK="${XDG_RUNTIME_DIR}/podman/podman.sock"
  fi
  # Environment for every future login shell + this one
  $SUDO tee /etc/profile.d/amli-podman.sh >/dev/null <<EOF
# Added by AMLI-prereqs: lets docker-compose talk to Podman
export PODMAN_COMPOSE_PROVIDER=/usr/local/bin/docker-compose
export DOCKER_HOST=unix://\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}/podman/podman.sock
[ "\$(id -u)" = 0 ] && export DOCKER_HOST=unix:///run/podman/podman.sock
EOF
  echo "Podman socket: $SOCK"
else
  say "4/6 Docker detected - nothing to wire"
fi

say "5/6 Firewall"
if command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state >/dev/null 2>&1; then
  $SUDO firewall-cmd --permanent --add-port=8443/tcp && $SUDO firewall-cmd --reload
  echo "Opened 8443/tcp (firewalld)"
elif command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
  $SUDO ufw allow 8443/tcp
  echo "Opened 8443/tcp (ufw)"
elif command -v iptables >/dev/null 2>&1 && $SUDO iptables -S INPUT 2>/dev/null | grep -q -- '-P INPUT \(DROP\|REJECT\)'; then
  $SUDO iptables -C INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null || $SUDO iptables -I INPUT -p tcp --dport 8443 -j ACCEPT
  echo "Opened 8443/tcp (iptables, NOT persistent across reboot - use your distro's iptables-save if needed)"
else
  echo "No active host firewall detected - nothing to open."
fi

say "6/6 Bundled container images"
if [ -d "$HERE/payload/base" ] && [ -d "$HERE/payload/app" ]; then
  echo "Loading images shipped inside this repo (./payload) - no registry or release download needed."
  bash "$HERE/load-images.sh" --local "$HERE/payload/base"
  bash "$HERE/load-images.sh" --local "$HERE/payload/app"
elif [ -n "${AMLI_IMAGES_REPO:-}" ]; then
  bash "$HERE/load-images.sh" "$AMLI_IMAGES_REPO" "${AMLI_IMAGES_TAG:-images-base-v1}"
else
  echo "No ./payload folder found. Make sure the clone is complete (git pull)."
fi

say "Done"
cat <<'EOF'
Prerequisites are installed. Now open a NEW shell (or: source /etc/profile.d/amli-podman.sh) and:

  git clone https://github.com/<you>/AMLI.git
  cd AMLI && bash deploy.sh
EOF
