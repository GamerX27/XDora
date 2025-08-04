#!/usr/bin/env bash
set -euo pipefail

#---------- helpers -----------------------------------------------------------
msg() { printf '\e[1;32m==>\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m!!\e[0m %s\n' "$*" ; exit 1; }

need_cmd() { command -v "$1" &>/dev/null || die "Required cmd '$1' not found."; }
need_cmd dnf
need_cmd flatpak
need_cmd lspci

#---------- 1. RPM Fusion ------------------------------------------------------
msg "Enabling RPM Fusion Free & Non-Free"
dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" :contentReference[oaicite:0]{index=0}

#---------- 2. Flathub ---------------------------------------------------------
msg "Switching to Flathub"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo :contentReference[oaicite:1]{index=1}
if flatpak remote-list | grep -q '^fedora'; then
  flatpak remote-delete -y fedora :contentReference[oaicite:2]{index=2}
fi
flatpak remote-modify --no-filter --enable flathub :contentReference[oaicite:3]{index=3}

#---------- 3. Core multimedia codecs -----------------------------------------
msg "Swapping in full FFmpeg and refreshing @multimedia"
dnf -y swap ffmpeg-free ffmpeg --allowerasing :contentReference[oaicite:4]{index=4}
dnf -y groupupdate multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin :contentReference[oaicite:5]{index=5}

#---------- 4. Optional GPU-accelerated codecs --------------------------------
detect_gpu() {
  lspci -nnk | awk '/VGA|3D/{print tolower($0); exit}'
}

gpu_line=$(detect_gpu)
case "$gpu_line" in
  *intel*)
      choice="intel"
      ;;
  *amd*|*ati*)
      choice="amd"
      ;;
  *)
      printf "\nHardware not recognised (or NVIDIA/VM). Choose codec set [intel/amd/skip] : "
      read -r choice
      ;;
esac

if [[ "${choice}" == "intel" ]]; then
  msg "Installing Intel VA-API drivers"
  if grep -qE 'Gen[56789]|i[3-9]-[6-9]|arc' <<<"$gpu_line"; then
      # Recent gens
      dnf -y install intel-media-driver :contentReference[oaicite:6]{index=6}
  else
      dnf -y install libva-intel-driver :contentReference[oaicite:7]{index=7}
  fi
elif [[ "${choice}" == "amd" ]]; then
  msg "Swapping Mesa VA/VDPAU drivers to Freeworld versions"
  for pkg in mesa-va-drivers mesa-vdpau-drivers; do
      dnf -y swap "${pkg}" "${pkg}-freeworld" || true
      # 32-bit compatibility (Steam / Wine) – ignore if not installed
      dnf -y swap "${pkg}.i686" "${pkg}-freeworld.i686" || true
  done :contentReference[oaicite:8]{index=8}
else
  msg "Skipping GPU-specific codec step."
fi

#---------- 5. Finish ----------------------------------------------------------
msg "All done. Reboot recommended to load any new media drivers."
