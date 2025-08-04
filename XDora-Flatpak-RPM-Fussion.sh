install_multimedia_codecs() {
  echo "→ Enabling RPM Fusion multimedia & codec packages (Fedora 40+ / DNF 5)"

  # Detect whether DNF 5 or older is installed, and set wrapper
  # (Fedora 40+ includes dnf5 and symlinks /usr/bin/dnf to dnf5)
  if command -v dnf5 >/dev/null 2>&1; then
    PKGMGR="dnf5"
  else
    PKGMGR="dnf"
  fi
  echo "Using pkg manager: $PKGMGR"

  # Helper: run DNF group commands—fallback to dnf4 if available
  group_update() {
    GROUP="$1"
    echo "Upgrading Fedora group '$GROUP' (${PKGMGR})"
    sudo $PKGMGR group upgrade -y "$GROUP" --with-optional --allowerasing || {
      if command -v dnf4 >/dev/null; then
        echo "DNF5 didn’t include RPM‑Fusion extras—falling back to dnf4 for group '$GROUP'"
        sudo dnf4 group upgrade -y "$GROUP" --with-optional --allowerasing
      else
        echo "Failed to update group '$GROUP' with dnf5 and no dnf4 available" >&2
      fi
    }
  }

  sudo $PKGMGR update --refresh -y

  # Swap base Fedora ffmpeg-free for full RPM‑Fusion ffmpeg
  sudo $PKGMGR swap -y ffmpeg-free ffmpeg --allowerasing

  # Update Fedora-defined @multimedia and @sound‑and‑video groups,
  # but manually add RPM‑Fusion extras since dnf5 may ignore them
  group_update multimedia
  group_update "sound‑and‑video"

  # RPM‑Fusion specific extras that Fedora’s group may omit under dnf5
  EXTRA_RPMFUSION=(
    libavcodec‑freeworld
    gstreamer1‑plugins‑bad‑freeworld
    gstreamer1‑plugins‑ugly‑freeworld
    ffmpeg‑full
    pipewire‑codec‑aptx
  )
  echo "Installing RPM‑Fusion codec extras (if needed): ${EXTRA_RPMFUSION[*]}"
  sudo $PKGMGR install -y "${EXTRA_RPMFUSION[@]}" || {
    # on i386/x86_64, also try installing .i686 variants
    sudo $PKGMGR install -y "${EXTRA_RPMFUSION[@]/%/.i686}" || true
  }

  # VA‑API / hardware‑acceleration support
  echo "Installing VA‑API hardware‑accel packages"
  sudo $PKGMGR install -y libva libva-utils ffmpeg-libs

  if lspci | grep -iq "Intel.*HD.*Graphics"; then
    echo "Detected Intel GPU → installing media‑driver"
    sudo $PKGMGR swap -y libva-intel-media-driver intel-media-driver --allowerasing
    sudo $PKGMGR install -y libva-intel-driver
  elif lspci | grep -iq "AMD"; then
    echo "Detected AMD GPU → swapping to freeworld mesa‑va/drivers"
    sudo $PKGMGR swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing
    sudo $PKGMGR swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing
    sudo $PKGMGR swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 --allowerasing
    sudo $PKGMGR swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686 --allowerasing
  else
    echo "No Intel/AMD GPU detected—assuming either VM or unsupported hardware"
  fi

  echo "Installing OpenH264 support"
  sudo $PKGMGR install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264
  sudo $PKGMGR config-manager --setopt=fedora-cisco-openh264.enabled=1

  echo "Multimedia & codec setup complete."
}
