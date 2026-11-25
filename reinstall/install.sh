#!/usr/bin/env bash
# Install q2-offload and restore the local Q2 customizations.
set -euo pipefail

PRINTER_IP="${1:-192.168.3.210}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
Q2="${Q2_OFFLOAD_DIR:-${HOME}/q2-offload}"
CFG="${PRINTER_CONFIG_DIR:-${HOME}/printer_data/config}"
TAG="${Q2_TAG:-v2026.11.25}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null || die "git is required"
command -v sudo >/dev/null || die "sudo is required"

if [ ! -d "${Q2}/.git" ]; then
    log "Cloning q2-offload"
    git clone https://github.com/cedbossneo/q2-offload.git "${Q2}"
fi

cd "${Q2}"
git fetch --quiet --tags --prune origin
git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null \
    || die "q2-offload tag ${TAG} not found; set Q2_TAG to a valid tag"
log "Checking out q2-offload ${TAG}"
git checkout --quiet --force --detach "${TAG}"

if ! git log -1 --format=%s | grep -q '^Local: pin Happy Hare'; then
    log "Applying local q2-offload patch"
    git am --quiet -3 --committer-date-is-author-date \
        "${SRC}/reinstall/q2-offload-local.patch"
fi

if [ ! -d "${CFG}/.git" ]; then
    log "Installing the config repository into ${CFG}"
    mkdir -p "$(dirname "${CFG}")"
    cp -a "${SRC}" "${CFG}"
fi

log "Running the q2-offload installer (interactive)"
./install.sh --printer "${PRINTER_IP}"

log "Applying local Moonraker changes and update-manager branches"
"${CFG}/reinstall/restore.sh"

log "Installing the pinned Happy Hare"
./install.sh update

log "Refreshing update-manager pins"
"${CFG}/reinstall/restore.sh"

log "Done. Run: cd ${Q2} && ./install.sh check"
