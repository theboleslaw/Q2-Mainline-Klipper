#!/usr/bin/env bash
# Apply the local q2-offload/Moonraker patches and normalize Moonraker's
# update-manager branches. Safe to run repeatedly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
Q2="${Q2_OFFLOAD_DIR:-${HOME}/q2-offload}"
MR="${MOONRAKER_DIR:-${HOME}/moonraker}"
CFG="${PRINTER_CONFIG_DIR:-${HOME}/printer_data/config}"
SKIP_RESTART="${SKIP_RESTART:-0}"

log() { printf '==> %s\n' "$*"; }

apply_patch_if_missing() {
    local dir="$1" subject="$2" patch="$3"
    [ -d "${dir}/.git" ] || return 0
    if git -C "${dir}" log -1 --format=%s | grep -qF "${subject}"; then
        return 0
    fi
    log "Applying $(basename "${patch}") to ${dir}"
    git -C "${dir}" am --quiet -3 --committer-date-is-author-date "${patch}"
}

# q2-offload: keep the local pin/patches/overrides on a branch that tracks main.
if [ -d "${Q2}/.git" ]; then
    git -C "${Q2}" fetch --quiet origin
    if ! git -C "${Q2}" log -1 --format=%s | grep -qF 'Local: pin Happy Hare'; then
        git -C "${Q2}" checkout --quiet -B main origin/main
    fi
    apply_patch_if_missing "${Q2}" 'Local: pin Happy Hare' \
        "${ROOT}/reinstall/q2-offload-local.patch"
    git -C "${Q2}" branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
fi

# Moonraker: local MMU log rollover + mmu_server component.
if [ -d "${MR}/.git" ]; then
    git -C "${MR}" fetch --quiet origin
    if ! git -C "${MR}" log -1 --format=%s | grep -qF 'Local: add MMU log rollover'; then
        git -C "${MR}" checkout --quiet -B master origin/master
    fi
    apply_patch_if_missing "${MR}" 'Local: add MMU log rollover' \
        "${ROOT}/reinstall/moonraker-mmu-log.patch"
    # q2-offload leaves Moonraker detached; reattach it so the update manager
    # does not warn about a detached HEAD.
    if ! git -C "${MR}" symbolic-ref -q HEAD >/dev/null; then
        git -C "${MR}" checkout --quiet -B master HEAD
    fi
    git -C "${MR}" branch --set-upstream-to=origin/master master >/dev/null 2>&1 || true
fi

# Repos without local changes: simply use their tracking branches.
if [ -d "${HOME}/mainsail-config/.git" ]; then
    git -C "${HOME}/mainsail-config" checkout --quiet master
fi
if [ -d "${HOME}/moonraker-timelapse/.git" ]; then
    git -C "${HOME}/moonraker-timelapse" checkout --quiet main
fi

# Klipper carries q2-offload's patches. Keep it on the q2-offload branch (the
# tree q2-offload checks out; it is not upstream master) and ignore the runtime
# extras (autopa, mesh toggle, Happy Hare symlinks) so it is not dirty.
if [ -d "${HOME}/klipper/.git" ]; then
    git -C "${HOME}/klipper" checkout --quiet -B q2-offload HEAD
    # The update manager needs a tracking remote to describe the branch; upstream
    # master is the right comparison even though the tree carries local patches.
    git -C "${HOME}/klipper" branch --set-upstream-to=origin/master q2-offload >/dev/null 2>&1 || true
    git -C "${HOME}/klipper" status --porcelain | awk '$1=="??"{print "/" substr($0,4)}' \
        >> "${HOME}/klipper/.git/info/exclude"
    sort -u "${HOME}/klipper/.git/info/exclude" -o "${HOME}/klipper/.git/info/exclude"
fi

# Pin the local Klipper/Moonraker commits and hide the expected "diverged"
# notice. q2-offload is updated from a terminal because it has local patches.
if [ -f "${CFG}/moonraker.conf" ]; then
    KH="$(git -C "${HOME}/klipper" rev-parse HEAD 2>/dev/null || true)"
    MH="$(git -C "${MR}" rev-parse HEAD 2>/dev/null || true)"
    python3 - "${CFG}/moonraker.conf" "${KH}" "${MH}" <<'PY'
import re
import sys

path, klipper_hash, moonraker_hash = sys.argv[1:4]


def drop_section(text, name):
    return re.sub(
        r"\n\[update_manager %s\]\n(?:[^\[\n].*\n|\n)*" % re.escape(name),
        "\n", text)


with open(path) as f:
    s = f.read()

s = drop_section(s, "q2-offload")
s = drop_section(s, "klipper")
s = drop_section(s, "moonraker")

block = ""
if klipper_hash:
    block += (
        "[update_manager klipper]\n"
        f"pinned_commit: {klipper_hash}\n"
        "report_anomalies: false\n\n")
if moonraker_hash:
    block += (
        "[update_manager moonraker]\n"
        f"pinned_commit: {moonraker_hash}\n"
        "report_anomalies: false\n\n")

marker = "[update_manager timelapse]"
if marker in s:
    s = s.replace(marker, block + marker, 1)
else:
    s = s.rstrip("\n") + "\n\n" + block

with open(path, "w") as f:
    f.write(s)
PY
fi

if [ "${SKIP_RESTART}" = "1" ]; then
    log "SKIP_RESTART=1: restart Moonraker manually with: sudo systemctl restart moonraker"
else
    log "Restarting Moonraker"
    sudo systemctl restart moonraker
fi
