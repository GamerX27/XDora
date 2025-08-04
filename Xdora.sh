#!/bin/bash
set -e

echo "== Fedora KDE Minimal Install + GUI Debranding =="

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root."
  exit 1
fi

echo "[1/6] Updating base system..."
dnf5 upgrade -y

echo "[2/6] Installing KDE Plasma Desktop with most features..."
dnf5 group install -y "KDE Plasma Workspaces"
dnf5 install -y \
  sddm \
  konsole \
  dolphin \
  kwrite \
  ark \
  kfind \
  kcalc \
  gwenview \
  okular \
  spectacle \
  filelight \
  kde-connect \
  kde-print-manager \
  plasma-discover \
  breeze-gtk \
  kde-cli-tools \
  xorg-x11-server-Xorg

echo "[3/6] Enabling graphical target and SDDM..."
systemctl set-default graphical.target
systemctl enable sddm

echo "[4/6] Replacing Fedora branding..."
dnf5 swap -y fedora-logos generic-logos

echo "[5/6] Debranding SDDM..."
mkdir -p /etc/sddm.conf.d/
cat > /etc/sddm.conf.d/debrand.conf <<EOF
[Theme]
Current=breeze

[General]
InputMethod=
EOF

# Optional: set neutral Plymouth boot splash
plymouth-set-default-theme -R details

echo "[6/6] Removing unneeded KDE/GUI bloat (preserving common tools)..."
dnf5 remove -y \
  libreoffice* \
  akonadi-import-wizard \
  kmail \
  korganizer \
  kontact \
  calligra* \
  elisa-player \
  dragonplayer \
  firefox \
  kamoso \
  kwalletmanager \
  kget || true

dnf5 autoremove -y
dnf5 clean all

echo "✅ Done! Reboot and enjoy your KDE environment with most features restored."
