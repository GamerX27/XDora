install_flatpak_and_block_fedora() {
  echo "🚫 Managing Flatpak: removing Fedora Remote, enforcing Flathub, blocking future use."

  # 0. Check if flatpak is installed; skip if not
  if ! command -v flatpak >/dev/null 2>&1; then
    echo "• Flatpak is not installed. Skipping Flatpak configuration."
    return
  fi

  # 1. Remove any flatpak apps using the 'fedora' remote
  echo "• Removing all Flatpak apps installed from Fedora remote (if any)."
  flatpak list --app --columns=application,remote | grep -E "\s+fedora\$" | \
    awk '{print $1}' | \
    while read -r app; do
      echo "  • Uninstalling $app from Fedora remote"
      sudo flatpak uninstall --system --delete-data -y "$app"
    done

  # 2. Remove the Fedora remote entirely
  echo "• Deleting Fedora remote to prevent future installs."
  sudo flatpak remote-delete --system --if-exists fedora

  # 3. Add Flathub (if missing) and ensure it's enabled
  echo "• Adding Flathub remote (or re-enabling if present but disabled)."
  if flatpak remote-list --system | grep -q "^flathub\s"; then
    sudo flatpak remote-modify --system --no-filter --enable flathub || true
    echo "  → Flathub already exists; enabled."
  else
    sudo flatpak remote-add --system --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo
    echo "  → Flathub added."
  fi

  # 4. Optional: for user installations, repeat using --user
  # (especially useful for pre-existing Dew desktop)
  flatpak remote-list --user | grep -q "^fedora\s" && {
    flatpak list --user --app --columns=application,remote | grep -E "\s+fedora\$" | \
      awk '{print $1}' | \
      while read -r app; do
        echo "  • Removing user-$app from Fedora remote"
        flatpak uninstall --user --delete-data -y "$app"
      done
    flatpak remote-delete --user --if-exists fedora
  }

  # 5. Block Fedora remote from ever being re-added (static remotes override)
  echo "• Preventing re-addition of Fedora remote"
  local blockfile="/etc/flatpak/remotes.d/90-disable-fedora.repo"
  sudo sh -c "cat > '$blockfile'" <<EOF
[remote-fedora]
Name=Blocked: Fedora Flatpak remote
Enabled=false
Url=https://registry.fedoraproject.org/
EOF
  sudo chmod 644 "$blockfile"

  echo "✅ Flatpak now uses Flathub only, Fedora remote is disabled (blocked)."
}
