#!/usr/bin/env bash
# Prints everything needed to debug an AMLI install. Run:  bash diagnose.sh 2>&1 | tee diag.txt   then paste diag.txt
ENGINE=$(command -v podman || command -v docker)
echo "### date/os";  date; . /etc/os-release 2>/dev/null; echo "$PRETTY_NAME"; id -un
echo "### memory/disk"; free -m; df -h / "$HOME" | cat
echo "### selinux/firewall"; getenforce 2>&1; firewall-cmd --list-ports 2>&1 | head -2
echo "### checksums base"; (cd "$(dirname "$0")/payload/base" && ls -l && sha256sum -c SHA256SUMS 2>&1)
echo "### images"; $ENGINE images 2>&1
echo "### containers"; $ENGINE ps -a 2>&1
for c in db backend huey frontend caddy; do echo "### logs $c"; $ENGINE logs --tail 25 $c 2>&1; done
echo "### mssql tar"; ls -l ~/mssql*.tar.gz ~/*.bak 2>&1
