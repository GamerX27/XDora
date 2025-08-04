#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
FEDORA_VER="$(rpm -E %fedora)"
DNF5_CMD="$(command -v dnf5 || true)"
DNF4_CMD="$(command -v dnf4 || true)"

log()   { echo -n "[$SCRIPT_NAME] "; echo "$*"; }
die()   { echo "ERROR: $*"; exit 1; }
warn()  { echo "WARNING: $*"; }
info()  { echo "# $*"; }

check_root_or_sudo() {
  if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null; then
    die "This script requires either root or sudo. Run as 'sudo $0' or as root."
  fi
}

# Install RPM Fusion repos if not already
setup_rpmfusion() {
  info "Step 1: Enabling RPM Fusion Free and Non‑Free repositories…"
  REPOURL_BASE="https://download1.rpmfusion.org"
  sudo dnf install -y \
    "${REPOURL_BASE}/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "${REPOURL_BASE}/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
  && log "RPM Fusion repos enabled." || warn "Could not install RPM Fusion launchers; maybe already present."
  sudo dnf makecache || warn "Could not repolist; continuing anyway."
}

# Install multimedia, swap codecs & handle group bug
install_multimedia_codec_stack() {
  info "Step 2: Installing multimedia codecs, handling DNF 5 group ignore bug…"
  UTIL="${DNF5_CMD:-dnf}"
  log "Primary pkg manager: $UTIL"  
  # Swap ffmpeg
  sudo $UTIL swap -y ffmpeg-free ffmpeg --allowerasing
  CODECS=(libavcodec-freeworld ffmpeg-libs \
          gstreamer1-plugins-{bad,good,base} \
          gstreamer1-plugin-openh264 \
          gstreamer1-libav \
          lame*) || true
  log "Installing essential codecs: ${CODECS[*]}"
  sudo $UTIL install -y "${CODECS[@]}" || true

  GROUPS=("multimedia" "sound-and-video")
  for grp in "${GROUPS[@]}"; do
    log "Attempt group update: $grp"
    if [ -n "$DNF4_CMD" ] && $UTIL group info "$grp" | grep -q 'Packages$$'; then
      log "DNF5 ignoring this group's RPM Fusion extras—using dnf4 fallback"
      sudo dnf4 group upgrade --with-optional "$grp" -y \
        --setopt="install_weak_deps=False" \
        --exclude=PackageKit-gstreamer-plugin || true
    else
      sudo $UTIL group upgrade --with-optional "$grp" -y \
        --setopt="install_weak_deps=False" \
        --exclude=PackageKit-gstreamer-plugin || true
    fi
  done

  log "Dummy pause to flush caches…"
  sudo $UTIL clean expire-cache || true
}

# Detect GPU and install VA‑API hardware driver
install_hardware_accel_driver() {
  info "Step 3: Installing VA‑API hardware-accelerated driver (only if needed)…"
  sudo dnf install -y libva libva-utils --setopt=clean_requirements_on_remove=1 || true

  GPU_LINE="$(lspci | grep -i "3D controller\|VGA" | head -n1 || :)"
  CPU_LINE="$(awk 'NR==1 && /model name/ {print tolower($0)}' /proc/cpuinfo || :)"
  log "Detected hardware: lspci: '$GPU_LINE'; cpuinfo: '$CPU_LINE'"

  if grep -qi intel <<< "$GPU_LINE" || grep -qi intel <<< "$CPU_LINE"; then
    if grep -Eq "i[3456789]-[56789]" <<< "$CPU_LINE"; then
      log "Intel Broadwell+ detected → installing intel‑media‑driver (iHD)"
      sudo dnf install -y intel-media-driver libva-intel-driver
      export LIBVA_DRIVER_NAME=iHD
    else
      log "Intel older GPU detected → installing i965/libva‑intel‑driver"
      sudo dnf install -y libva-intel-driver
    fi

  elif grep -qi amd <<< "$GPU_LINE"; then
    log "AMD GPU detected → swapping to mesa-va-drivers-freeworld & vdpau"
    sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing || true
    sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing || true
    sudo dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 --allowerasing || true
    sudo dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686 --allowerasing || true

  elif grep -qi nvidia <<< "$GPU_LINE"; then
    log "NVIDIA GPU detected → installing libva‑nvidia‑driver"
    sudo dnf install -y libva-nvidia-driver

  else
    log "No Intel/AMD/NVIDIA GPU found → skipping VA‑API hardware drivers."
  fi
}

# Uninstall Fedora Remote Flatpaks, block future additions, add Flathub
install_flatpak_and_block_fedora() {
  info "Step 4: Removing Fedora Flatpak remote, blocking it, and enforcing Flathub only."
  if ! command -v flatpak >/dev/null; then
    warn "flatpak is not installed; skipping Flatpak management."
    return
  fi

  REMOTES_SYS="$(flatpak remote-list --system --columns=name)"
  echo "$REMOTES_SYS" | grep -qx fedora && {
    APPS="$(flatpak list --columns=application,remote | awk '$2=="fedora" {print $1}' || true)"
    log "Bulk removing all Fedora Remote apps: $APPS"
    for app in $APPS; do
      sudo flatpak uninstall --system --delete-data -y "$app"
    done
    log "Removing fedora remote from system flatpaks"
    sudo flatpak remote-delete --system --if-exists fedora
  }

  flatpak remote-list --user --columns=name | grep -qx fedora && {
    U_APPS="$(flatpak list --user --columns=application,remote | awk '$2=="fedora" {print $1}' || true)"
    log "Removing (user) Fedora Remote apps: $U_APPS"
    for app in $U_APPS; do
      flatpak uninstall --user --delete-data -y "$app"
    done
    log "Deleting the user-level Fedora remote"
    flatpak remote-delete --user --if-exists fedora
  }

  log "Adding or re-enabling Flathub remote"
  flatpak remote-list --system | grep -qx flathub \
    && sudo flatpak remote-modify --system --no-filter --enable flathub \
    || sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  BLOCK_FILE="/etc/flatpak/remotes.d/90-block-fedora.repo"
  log "Writing $BLOCK_FILE to prevent re-creation of Fedora remote"
  sudo tee "$BLOCK_FILE" >/dev/null <<EOF
[Remote "fedora"]
Name = Fedora (blocked)
Enabled = false
Url = https://registry.fedoraproject.org/
EOF
  sudo chmod 644 "$BLOCK_FILE"
  log "Fedora remote is now disabled and blocked. Flathub only."
}

main() {
  check_root_or_sudo
  [ "$FEDORA_VER" -lt 40 ] && die "This script only supports Fedora 40 or newer."

  setup_rpmfusion
  install_multimedia_codec_stack
  install_hardware_accel_driver
  install_flatpak_and_block_fedora

  info "🎉 Finished all tasks. You may want to reboot to fully activate VA‑API."
  echo "You can verify HW decoding by running (after reboot):"
  echo "  LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-auto} vainfo"
}

# Run main
main "$@"
