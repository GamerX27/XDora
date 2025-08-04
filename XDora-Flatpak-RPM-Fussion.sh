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
echo "📦 Configuring RPM Fusion..."
FEDORA_REL=$(rpm -E %fedora)

if ! dnf repolist --all | grep -qE '^rpmfusion-.*free'; then
  $SUDO dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_REL}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_REL}.noarch.rpm"
else
  echo "✅ RPM Fusion already enabled."
fi

###############################################################################
# 3. Cisco OpenH264 – Codec Repo
###############################################################################
echo "🎞️ Enabling Cisco OpenH264 repo..."
if dnf repolist --all | grep -qE '^fedora-cisco-openh264'; then
  if ! dnf repolist | grep -qE '^fedora-cisco-openh264'; then
    $SUDO dnf config-manager --set-enabled fedora-cisco-openh264
  fi
else
  echo "⚠️ Warning: 'fedora-cisco-openh264' repo not found."
fi

###############################################################################
# 4. System Update – @core and full update
###############################################################################
echo "🔄 Updating system core packages..."
$SUDO dnf -y update @core
$SUDO dnf -y update --refresh

###############################################################################
# 5. Multimedia Enhancements – manual install
###############################################################################
echo "🎧 Installing multimedia codecs manually..."

$SUDO dnf -y install \
  ffmpeg \
  gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free \
  gstreamer1-plugins-ugly \
  gstreamer1-plugins-base \
  gstreamer1-libav \
  lame \
  x264 \
  x265 \
  libheif-freeworld \
  pipewire-codec-aptx \
  libva-utils \
  vdpauinfo \
  vainfo

echo "🎞️ Swapping ffmpeg-free → full ffmpeg..."
$SUDO dnf -y swap ffmpeg-free ffmpeg --allowerasing

###############################################################################
# 6. Hardware Acceleration – Intel / AMD / Skip
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
    echo "  a) New Intel GPU (Broadwell+, Gen8+, e.g. Skylake, Tiger Lake)"
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
echo "You may want to reboot for all changes to apply."
