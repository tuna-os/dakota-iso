#!/usr/bin/bash
# Pre-install flatpaks into the live squashfs.
#
# Runs with --mount=type=cache,target=/var/lib/flatpak so the flatpak ostree
# repo persists across builds.  Each run reconciles to match /tmp/flatpaks-list:
#   - installs missing apps
#   - updates outdated apps (ostree delta, fast)
#   - removes apps that were dropped from the list
#
# /tmp/flatpaks-list is COPYd by the Containerfile so it's always current.
# Requires network at build time; CAP_SYS_ADMIN for dbus.

set -exo pipefail

# overlayfs inside Podman builds doesn't support O_TMPFILE; /dev/shm does.
export TMPDIR=/dev/shm
mkdir -p /run/dbus
dbus-daemon --system --fork --nopidfile
sleep 1

flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# bootc-installer bundle
curl --retry 3 --location \
    https://github.com/tuna-os/tuna-installer/releases/download/continuous/org.bootcinstaller.Installer.flatpak \
    -o /tmp/tuna-installer.flatpak
flatpak install --system --noninteractive --bundle /tmp/tuna-installer.flatpak || \
    flatpak update --system --noninteractive org.bootcinstaller.Installer
rm /tmp/tuna-installer.flatpak

flatpak override --system --filesystem=/etc:ro org.bootcinstaller.Installer

# ── Reconcile Flathub apps against the wanted list ───────────────────────────

readarray -t WANTED < <(grep -v '^[[:space:]]*#' /tmp/flatpaks-list | grep -v '^[[:space:]]*$')

# Install or update everything in the list (--or-update = skip if current)
# --no-related skips locale packs and debug symbols (~3 GB uncompressed)
flatpak install --system --noninteractive --no-related --or-update flathub "${WANTED[@]}"

# Remove any system app that is no longer in the wanted list
readarray -t INSTALLED < <(flatpak list --app --system --columns=application 2>/dev/null || true)
for app in "${INSTALLED[@]}"; do
    # Keep the installer regardless
    [[ "$app" == "org.bootcinstaller.Installer" ]] && continue
    if [[ ! " ${WANTED[*]} " =~ " ${app} " ]]; then
        echo "Removing dropped flatpak: $app"
        flatpak uninstall --system --noninteractive "$app" || true
    fi
done

# Prune unused runtimes left behind by removals
flatpak uninstall --system --noninteractive --unused || true
