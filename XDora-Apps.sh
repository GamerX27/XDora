#!/bin/bash

set -e

# Install Brave browser
echo "Installing Brave browser..."
curl -fsS https://dl.brave.com/install.sh | sh

# Update package index
echo "Updating package index..."
sudo dnf update

# Install VLC, Fastfetch, and Fish
echo "Installing VLC, Fastfetch, and Fish shell..."
sudo dnf install -y vlc fastfetch fish

# Set Fish as default shell
echo "Setting Fish as default shell..."
if ! grep -q "$(command -v fish)" /etc/shells; then
    echo "$(command -v fish)" | sudo tee -a /etc/shells
fi
chsh -s "$(command -v fish)"

echo "✅ Done! Please log out and log back in to use Fish as your default shell."
