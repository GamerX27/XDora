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
# 2. RPM Fusion – Free & Non-Free, Fully Enabled (DNF5-safe)
###############################################################################
echo "📦 Setting up RPM Fusion..."

FEDORA_REL=$(rpm -E %fedora)

$SUDO dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_REL}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_REL}.noarch.rpm"

echo "🔄 Refreshing metadata..."
$SUDO dnf clean all
$SUDO dnf makecache

ENABLED_REPOS=(
  rpmfusion-free
  rpmfusion-free-updates
  rpmfusion-nonfree
  rpmfusion-nonfree-updates
)

for repo in "${ENABLED_REPOS[@]}"; do
  if ! dnf repolist enabled | grep -q "^$repo"; then
    echo "✅ Enabling $repo..."
    $SUDO dnf config-manager enable "$repo"
  else
    echo "✔️  $repo already enabled"
  fi
done

echo "✅ RPM Fusion fully configured."

###############################################################################
# 3. Multimedia Enhancements – try group, fallback to manual
###############################################################################
echo "🎧 Installing multimedia stack..."

if dnf group info multimedia &>/dev/null; then
  echo "🧩 Installing multimedia group via DNF..."
  if ! $SUDO dnf -y group install "Multimedia" \
      --setopt=install_weak_deps=False \
      --exclude=PackageKit-gstreamer-plugin; then
    echo "⚠️ Group install failed. Falling back to manual packages..."
  fi
fi

MULTIMEDIA_PACKAGES=(
  ffmpeg
  gstreamer1-plugins-good
  gstreamer1-plugins-bad-free
  gstreamer1-plugins-ugly
  gstreamer1-plugins-base
  gstreamer1-libav
  lame
  x264
  x265
  libheif-freeworld
  pipewire-codec-aptx
  libva-utils
  vdpauinfo
  vainfo
)

AVAILABLE=()

for pkg in "${MULTIMEDIA_PACKAGES[@]}"; do
  if dnf list --quiet --available "$pkg" &>/dev/null; then
    AVAILABLE+=("$pkg")
  else
    echo "⚠️  Skipping unavailable package: $pkg"
  fi
done

if [[ ${#AVAILABLE[@]} -gt 0 ]]; then
  echo "📦 Installing available multimedia packages..."
  $SUDO dnf -y install "${AVAILABLE[@]}"
else
  echo "ℹ️ No multimedia packages to install — all unavailable or already present."
fi

echo "🎞️ Swapping ffmpeg-free → full ffmpeg..."
$SUDO dnf -y swap ffmpeg-free ffmpeg --allowerasing || echo "ℹ️ Swap skipped or already done."

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
