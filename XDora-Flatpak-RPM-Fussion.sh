#!/usr/bin/env bash
set -euo pipefail

FEDORA_VERSION=$(rpm -E %fedora)

log() { echo -e "\033[1;32m[XDora]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARNING]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    error "Please run this script as root or with sudo."
    exit 1
  fi
}

install_rpmfusion() {
  log "Enabling RPM Fusion repositories..."
  dnf install -y \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
}

install_multimedia_codecs() {
  log "Installing multimedia codecs from RPM Fusion..."

  # Swap ffmpeg-free with full ffmpeg
  dnf swap -y ffmpeg-free ffmpeg --allowerasing

  # Install recommended codecs
  dnf install -y \
    libavcodec-freeworld \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly-freeworld \
    gstreamer1-plugin-openh264 \
    lame\* \
    gstreamer1-plugins-base \
    gstreamer1-plugins-good \
    gstreamer1-libav \
    ffmpeg-libs || warn "Some codecs may already be installed or unavailable."
}

install_vaapi_drivers() {
  log "Detecting GPU and installing VA-API hardware acceleration drivers..."

  dnf install -y libva libva-utils

  GPU_INFO=$(lspci | grep -Ei 'VGA|3D')
  if echo "$GPU_INFO" | grep -qi 'intel'; then
    log "Intel GPU detected."

    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo)
    if echo "$CPU_MODEL" | grep -Eiq 'i[5-9]|xeon|core'; then
      log "Installing intel-media-driver (iHD)..."
      dnf install -y intel-media-driver libva-intel-driver
    else
      log "Installing legacy Intel VA-API driver..."
      dnf install -y libva-intel-driver
    fi

  elif echo "$GPU_INFO" | grep -qi 'amd'; then
    log "AMD GPU detected. Swapping to freeworld VAAPI drivers..."
    dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing
    dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing
    dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 --allowerasing
    dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686 --allowerasing

  elif echo "$GPU_INFO" | grep -qi 'nvidia'; then
    log "NVIDIA GPU detected. Installing VAAPI bridge..."
    dnf install -y libva-nvidia-driver

  else
    warn "No supported GPU detected. Skipping VA-API driver installation."
  fi
}

setup_flatpak_and_block_fedora() {
  log "Configuring Flatpak and removing Fedora remote..."

  # Install Flatpak if not present
  if ! command -v flatpak &>/dev/null; then
    log "Flatpak not found. Installing..."
    dnf install -y flatpak
  fi

  # Remove Fedora remote and apps (system)
  if flatpak remotes --system | grep -q "^fedora"; then
    log "Removing system Fedora Flatpak apps..."
    flatpak list --system --app --columns=application,remote | awk '$2=="fedora"{print $1}' | while read -r app; do
      flatpak uninstall --system --delete-data -y "$app"
    done
    flatpak remote-delete --system fedora
  fi

  # Remove Fedora remote and apps (user)
  if flatpak remotes --user | grep -q "^fedora"; then
    log "Removing user Fedora Flatpak apps..."
    flatpak list --user --app --columns=application,remote | awk '$2=="fedora"{print $1}' | while read -r app; do
      flatpak uninstall --user --delete-data -y "$app"
    done
    flatpak remote-delete --user fedora
  fi

  # Add Flathub
  if ! flatpak remotes | grep -q "^flathub"; then
    log "Adding Flathub Flatpak remote..."
    flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
  else
    log "Flathub is already added."
  fi

  # Block Fedora remote from being re-added
  BLOCK_FILE="/etc/flatpak/remotes.d/99-block-fedora.repo"
  log "Blocking Fedora Flatpak remote..."
  mkdir -p /etc/flatpak/remotes.d
  tee "$BLOCK_FILE" >/dev/null <<EOF
[remote-fedora]
Name=Blocked Fedora Remote
Enabled=false
Url=https://registry.fedoraproject.org/
EOF
  chmod 644 "$BLOCK_FILE"
  log "Fedora Flatpak remote has been blocked."
}

main() {
  check_root
  install_rpmfusion
  install_multimedia_codecs
  install_vaapi_drivers
  setup_flatpak_and_block_fedora
  log "✅ All done. You may want to reboot for all changes to take full effect."
}

main "$@"
