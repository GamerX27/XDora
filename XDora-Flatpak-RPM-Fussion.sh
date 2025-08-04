#!/usr/bin/env bash
set -euo pipefail

FEDORA_VER=$(rpm -E %fedora)

log() { echo "[XDora] $*"; }
warn() { echo "[WARNING] $*"; }

# 1. Enable RPM Fusion and install codecs + multimedia groups
enable_multimedia() {
  log "Enabling RPM Fusion repos..."
  sudo dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm

  log "Swapping ffmpeg-free → full ffmpeg"
  sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing

  log "Installing additional codecs per RPM Fusion Howto"
  sudo dnf install -y \
    libavcodec-freeworld \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly-freeworld \
    gstreamer1-plugin-openh264 \
    lame* \
    gstreamer1-plugins-{base,good,libav} \
    ffmpeg-libs || true

  log "Upgrading multimedia & sound‑and‑video groups"
  sudo dnf group upgrade -y multimedia --with-optional --setopt="install_weak_deps=False"
  sudo dnf group upgrade -y sound-and-video

  log "Installing VA‑API libs"
  sudo dnf install -y libva libva-utils
}

# 2. Install VA‑API drivers based on GPU vendor
install_vaapi_drivers() {
  GPU=$(lspci | grep -Ei 'VGA|3D' | head -n1 || :)
  log "Detected GPU: $GPU"

  if echo "$GPU" | grep -qi intel; then
    log "Installing Intel VA‑API driver"
    sudo dnf install -y intel-media-driver libva-intel-driver
  elif echo "$GPU" | grep -qi amd; then
    log "Installing AMD freeworld VA‑API drivers"
    sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing
    sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing
    sudo dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 --allowerasing
    sudo dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686 --allowerasing
  elif echo "$GPU" | grep -qi nvidia; then
    log "Installing NVIDIA VA‑API bridge"
    sudo dnf install -y libva-nvidia-driver
  else
    warn "No supported GPU detected — skipping VA‑API drivers."
  fi
}

# 3. Remove Fedora Flatpak remote/apps, enforce Flathub, install Discover backend
setup_flatpak() {
  log "Ensuring Flatpak & Flathub only; removing Fedora flatpak remote/apps…"
  sudo dnf install -y flatpak

  if flatpak remotes --system | grep -q '^fedora'; then
    flatpak list --system --app --columns=application,remote | awk '$2=="fedora"{print $1}' | \
      while read -r app; do
        log "Removing system Flatpak app from Fedora: $app"
        sudo flatpak uninstall --system --delete-data -y "$app"
      done
    sudo flatpak remote-delete --system fedora
  fi

  if flatpak remotes --user | grep -q '^fedora'; then
    flatpak list --user --app --columns=application,remote | awk '$2=="fedora"{print $1}' | \
      while read -r app; do
        log "Removing user Flatpak app from Fedora: $app"
        flatpak uninstall --user --delete-data -y "$app"
      done
    flatpak remote-delete --user fedora
  fi

  if flatpak remotes | grep -q '^flathub'; then
    sudo flatpak remote-modify --system --no-filter --enable flathub
    log "Flathub already exists — re-enabled."
  else
    log "Adding Flathub remote..."
    sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi

  sudo mkdir -p /etc/flatpak/remotes.d
  sudo tee /etc/flatpak/remotes.d/99-disable-fedora.repo >/dev/null <<EOF
[remote-fedora]
Name=Blocked Fedora Remote
Enabled=false
Url=https://registry.fedoraproject.org/
EOF

  log "Installing Plasma Discover backend for Flatpak support"
  sudo dnf install -y plasma-discover-backend-flatpak || warn "Discover backend may not be available."
}

main() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root or use sudo."
    exit 1
  fi

  enable_multimedia
  install_vaapi_drivers
  setup_flatpak

  echo "✅ Completed setup aligned with RPM Fusion Multimedia Howto :contentReference[oaicite:1]{index=1} and Fedora / Silverblue Flatpak cleanup approach :contentReference[oaicite:2]{index=2}."
  echo "You may want to reboot for VA‑API activation."
}

main
