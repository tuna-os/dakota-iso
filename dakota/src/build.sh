#!/usr/bin/bash
# Live-environment setup for the Dakota ISO installer image.
#
# Runs inside the final Dakota container stage with:
#   --cap-add sys_admin --security-opt label=disable
#
# At this point the initramfs has already been replaced (by the Debian
# initramfs-builder stage) with a dmsquash-live capable one.  This script
# only handles the runtime live-environment: user, GDM autologin, and
# the tuna-installer configuration + autostart.
#
# Flatpak pre-installation is intentionally omitted from the initial build
# to keep the ISO small and validate the boot path first.  Re-enable by
# uncommenting the flatpak section below once GDM/gnome-shell start cleanly.

set -exo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── VERSION_ID ────────────────────────────────────────────────────────────────
# GNOME OS omits VERSION_ID from os-release; image-builder and bootc tooling
# require it.  Replace if present, append if missing.
if grep -q '^VERSION_ID=' /usr/lib/os-release 2>/dev/null; then
    sed -i 's/^VERSION_ID=.*/VERSION_ID=latest/' /usr/lib/os-release
else
    echo 'VERSION_ID=latest' >> /usr/lib/os-release
fi

# ── Live user ─────────────────────────────────────────────────────────────────
# GNOME OS has no livesys-scripts; create a passwordless live user manually.
useradd --create-home --uid 1000 --user-group \
    --comment "Live User" liveuser || true
passwd --delete liveuser

# Skip gnome-initial-setup in the live session so GNOME Shell starts directly
mkdir -p /home/liveuser/.config
touch /home/liveuser/.config/gnome-initial-setup-done
chown -R liveuser:liveuser /home/liveuser/.config

# ── GDM autologin ─────────────────────────────────────────────────────────────
mkdir -p /etc/gdm
cat > /etc/gdm/custom.conf << 'GDMEOF'
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=liveuser
GDMEOF

# ── /var/tmp tmpfs ────────────────────────────────────────────────────────────
# The live overlayfs puts /var on a small RAM overlay.  bootc needs substantial
# space in /var/tmp when staging an install; mount a dedicated tmpfs there.
cat > /usr/lib/systemd/system/var-tmp.mount << 'UNITEOF'
[Unit]
Description=Large tmpfs for /var/tmp in the live environment

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%,nr_inodes=1m

[Install]
WantedBy=local-fs.target
UNITEOF
systemctl enable var-tmp.mount

# ── Tuna-installer configuration ──────────────────────────────────────────────
mkdir -p /etc/tuna-installer
cp "$SCRIPT_DIR/etc/tuna-installer/images.json" /etc/tuna-installer/images.json
cp "$SCRIPT_DIR/etc/tuna-installer/recipe.json"  /etc/tuna-installer/recipe.json

# Autostart tuna-installer when the live GNOME session begins
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/tuna-installer.desktop << 'DTEOF'
[Desktop Entry]
Name=Dakota Installer
Exec=flatpak run org.bootcinstaller.Installer
Type=Application
X-GNOME-Autostart-enabled=true
DTEOF

# ── Flatpak pre-installation (optional — deferred until boot is validated) ────
# Uncomment to pre-install tuna-installer + Bluefin system flatpaks.
# Requires network access at build time and adds ~1-3 GB to the ISO.
#
# mkdir -p /etc/flatpak/remotes.d
# curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
#     https://dl.flathub.org/repo/flathub.flatpakrepo
# xargs flatpak install -y --noninteractive --system < "$SCRIPT_DIR/flatpaks"
