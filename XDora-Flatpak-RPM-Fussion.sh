#!/usr/bin/env bash

set -euo pipefail

### Sudo wrapper
if [[ $EUID -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

echo "🔧 Starting Fedora Desktop Setup…"

###############################################################################
# 1. Flatpak – Flathub remote setup
###############################################################################
echo "📦 Configuring Flatpak…"
if ! command -v flatpak >/dev/null 2>&1; then
  echo "❌ Flatpak not found. Install Flatpak and re-run this script." >&2
  exit 1
fi

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if flatpak remotes --columns=name | grep -qx "fedora"; then
  flatpak remote-delete fedora
fi
echo "✅ Flatpak configured."

###############################################################################
# 2. RPM Fusion – Repositories
###############################################################################
echo "📦 Configuring RPM Fusion…"
FEDORA_REL=$(rpm -E %fedora)

if ! dnf repolist --all | grep -qE '^rpmfusion-.*free'; then
  $SUDO dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_REL}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_REL}.noarch.rpm"
else
  echo "✅ RPM Fusion already configured."
fi

###############################################################################
# 3. Cisco OpenH264 – Codec Repo
###############################################################################
echo "🎞️ Enabling Cisco OpenH264 repo…"
if dnf repolist --all | grep -qE '^fedora-cisco-openh264'; then
  if ! dnf repolist | grep -qE '^fedora-cisco-openh264'; then
    $SUDO dnf config-manager --set-enabled fedora-cisco-openh264
  fi
else
  echo "⚠️ Warning: 'fedora-cisco-openh264' repo not found in configuration."
fi

###############################################################################
# 4. System Update – @core and full system
###############################################################################
echo "🔄 Updating core packages and system…"
$SUDO dnf -y update @core
$SUDO dnf -y update --refresh

###############################################################################
# 5. Multimedia Enhancements – ffmpeg, @multimedia
###############################################################################
echo "🎧 Installing full ffmpeg and updating multimedia stack…"
$SUDO dnf -y swap ffmpeg-free ffmpeg --allowerasing
$SUDO dnf -y update @multimedia \
  --setopt=install_weak_deps=False \
  --exclude=PackageKit-gstreamer-plugin

###############################################################################
# 6. Hardware Accelerated Codec Setup – Intel / AMD / Skip
###############################################################################
echo
echo "🖥️ Hardware Acceleration Setup:"
echo "  1) Intel GPU"
echo "  2) AMD GPU"
echo "  3) Skip (VM or unsupported system)"
read -rp "Select your GPU type (1/2/3): " GPU_CHOICE

case "$GPU_CHOICE" in
  1)
    echo "Intel GPU selected."
    echo "  a) New Intel GPU (Broadwell+, Skylake, Tiger Lake, etc.)"
    echo "  b) Old Intel GPU (Ivy Bridge, Haswell, etc.)"
    read -rp "Select Intel driver type (a/b): " INTEL_TYPE

    case "$INTEL_TYPE" in
      a|A)
        $SUDO dnf -y install intel-media-driver libva-utils vainfo
        ;;
      b|B)
        $SUDO dnf -y install libva-intel-driver libva-utils vainfo
        ;;
      *)
        echo "Invalid Intel driver choice. Skipping Intel install."
        ;;
    esac
    ;;
  2)
    echo "AMD GPU selected. Swapping Mesa VAAPI/VDPAU drivers with Freeworld…"
    $SUDO dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld
    $SUDO dnf -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    $SUDO dnf -y swap mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
    $SUDO dnf -y swap mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
    $SUDO dnf -y install libva-utils vdpauinfo vainfo
    ;;
  3)
    echo "Skipping hardware acceleration setup."
    ;;
  *)
    echo "Invalid selection. Skipping GPU driver setup."
    ;;
esac

###############################################################################
# Done
###############################################################################
echo
echo "🎉 Fedora Desktop setup complete!"
echo "  ✔️ Flathub added"
echo "  ✔️ RPM Fusion enabled"
echo "  ✔️ Cisco H.264 repo enabled"
echo "  ✔️ System updated"
echo "  ✔️ Multimedia stack ready"
echo "  ✔️ GPU drivers configured (if selected)"
