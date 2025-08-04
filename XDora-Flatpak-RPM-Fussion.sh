#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

echo "🔧 Starting Fedora Desktop Setup..."

###############################################################################
# 1. Flatpak – Flathub setup
###############################################################################
echo "📦 Configuring Flatpak..."
if ! command -v flatpak &>/dev/null; then
  echo "❌ Flatpak not found. Install it and re-run this script." >&2
  exit 1
fi

$SUDO flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if flatpak remotes --columns=name | grep -qx "fedora"; then
  $SUDO flatpak remote-delete fedora
fi
echo "✅ Flatpak configured."

###############################################################################
# 2. RPM Fusion – Free & Non-Free
###############################################################################
echo "📦 Setting up RPM Fusion..."
FEDORA_REL=$(rpm -E %fedora)

$SUDO dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_REL}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_REL}.noarch.rpm"

$SUDO dnf clean all
$SUDO dnf makecache

###############################################################################
# 3. Multimedia – YOUR FIX
###############################################################################
echo "🎧 Installing multimedia support using your instructions..."

$SUDO dnf4 group install multimedia -y
$SUDO dnf swap 'ffmpeg-free' 'ffmpeg' --allowerasing .y
$SUDO dnf group install -y sound-and-video

###############################################################################
# 4. Cisco OpenH264 – Codec Repo
###############################################################################
echo "🎞️ Enabling Cisco OpenH264 repo..."
if dnf repolist --all | grep -qE '^fedora-cisco-openh264'; then
  if ! dnf repolist | grep -qE '^fedora-cisco-openh264'; then
    $SUDO dnf config-manager enable fedora-cisco-openh264
  fi
else
  echo "⚠️ Warning: 'fedora-cisco-openh264' repo not found."
fi

###############################################################################
# 5. System Update – core and full update
###############################################################################
echo "🔄 Updating system..."
$SUDO dnf -y update @core
$SUDO dnf -y update --refresh

###############################################################################
# 6. GPU Acceleration – Intel / AMD / Skip
###############################################################################
echo
echo "🖥️ GPU Acceleration Setup:"
echo "  1) Intel GPU"
echo "  2) AMD GPU"
echo "  3) Skip (for VM/headless)"
read -rp "Select your GPU type (1/2/3): " GPU_CHOICE

case "$GPU_CHOICE" in
  1)
    echo "Intel GPU selected."
    echo "  a) New Intel GPU (Broadwell+, Gen8+)"
    echo "  b) Old Intel GPU (Ivy Bridge, Haswell)"
    read -rp "Select Intel driver type (a/b): " INTEL_TYPE

    case "$INTEL_TYPE" in
      a|A)
        $SUDO dnf -y install intel-media-driver libva-utils vainfo
        ;;
      b|B)
        $SUDO dnf -y install libva-intel-driver libva-utils vainfo
        ;;
      *)
        echo "Invalid Intel driver choice. Skipping."
        ;;
    esac
    ;;
  2)
    echo "AMD GPU selected. Installing Freeworld drivers..."
    $SUDO dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld
    $SUDO dnf -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    $SUDO dnf -y swap mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
    $SUDO dnf -y swap mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
    $SUDO dnf -y install libva-utils vdpauinfo vainfo
    ;;
  3)
    echo "Skipping GPU hardware acceleration setup."
    ;;
  *)
    echo "Invalid selection. Skipping GPU driver install."
    ;;
esac

###############################################################################
# Done
###############################################################################
echo
echo "✅ Fedora Desktop setup complete!"
echo "🔁 Reboot recommended."
