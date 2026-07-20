#!/usr/bin/env bash
# Keep the root filesystem from ever filling up (which would break sshd, k3s, etc.).
# Runs on a timer: if free space drops below the threshold, reclaim aggressively.
set -euo pipefail

THRESHOLD_PCT="${DISK_GUARD_THRESHOLD_PCT:-85}"   # act when Use% >= this
used_pct=$(df --output=pcent / | tail -1 | tr -dc '0-9')

log() { logger -t disk-guard "$*"; echo "disk-guard: $*"; }

if [ "$used_pct" -lt "$THRESHOLD_PCT" ]; then
  log "ok: root at ${used_pct}% (< ${THRESHOLD_PCT}%)"
  exit 0
fi

log "root at ${used_pct}% >= ${THRESHOLD_PCT}% — reclaiming"

# 1) Unused container images in k3s/containerd (the usual culprit).
if command -v k3s >/dev/null 2>&1; then
  k3s crictl rmi --prune >/dev/null 2>&1 || true
fi
# 2) Docker leftovers (legacy stack + build cache).
if command -v docker >/dev/null 2>&1; then
  docker system prune -af >/dev/null 2>&1 || true
fi
# 3) Vacuum journald to a hard cap.
journalctl --vacuum-size=200M >/dev/null 2>&1 || true
# 4) Old apt archives.
apt-get clean >/dev/null 2>&1 || true

now_pct=$(df --output=pcent / | tail -1 | tr -dc '0-9')
log "done: root now at ${now_pct}%"
