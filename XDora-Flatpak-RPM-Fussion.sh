#!/bin/bash

# Script for XDora - Fedora-like Distro

# Function to remove Fedora's Flatpak packages
remove_fedora_flatpaks() {
    echo "Removing Fedora's Flatpak packages..."

    # List all Flatpak applications installed
    flatpak list --app | while read app; do
        echo "Removing Flatpak application: $app"
        flatpak uninstall -y $app
    done
}

# Function to add Flathub repository
add_flathub_repo() {
    echo "Adding Flathub repository to Flatpak..."
    
    # Check if Flathub is already added
    if ! flatpak remotes | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        echo "Flathub added successfully!"
    else
        echo "Flathub is already added."
    fi
}

# Function to check if Plasma Discover is installed
check_plasma_discover() {
    echo "Checking if Plasma Discover is installed..."

    # Check if Plasma Discover is installed
    if ! command -v plasma-discover &> /dev/null; then
        echo "Plasma Discover is not installed. Installing..."
        sudo dnf install -y plasma-discover
    else
        echo "Plasma Discover is already installed."
    fi
}

# Function to enable RPM Fusion repositories
enable_rpmfusion() {
    echo "Enabling RPM Fusion repositories..."

    # Install RPM Fusion free and nonfree repositories
    sudo dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

    # Enable the openh264 library on Fedora 41 and later
    if [ "$(rpm -E %fedora)" -ge 41 ]; then
        echo "Enabling Cisco OpenH264 repository..."
        sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

        # Install rpmfusion-appstream-data explicitly for Fedora 41 and later
        echo "Installing rpmfusion-appstream-data packages..."
        sudo dnf install -y rpmfusion-\*-appstream-data
    fi
}

# Function to install multimedia codecs
install_multimedia_codecs() {
    echo ""
    echo "Installing multimedia codecs and plugins..."

    # Install individual multimedia packages
    sudo dnf install -y \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly-freeworld \
    gstreamer1-libav \
    ffmpeg \
    libdvdcss

    echo "Proprietary FFmpeg and multimedia packages have been installed/updated."
}

# Function to check if the user has an Intel iGPU or AMD APU/GPU
ask_for_gpu() {
    echo ""
    read -p "Do you have an Intel integrated GPU (iGPU) or an AMD APU/GPU? (intel/amd): " gpu_type

    if [[ "$gpu_type" == "intel" || "$gpu_type" == "Intel" ]]; then
        echo "Installing drivers for Intel iGPU..."
        
        # Check if the Intel processor is 6th generation or later
        read -p "Is your Intel processor 6th generation or later? (y/n): " intel_gen
        if [[ "$intel_gen" == "y" || "$intel_gen" == "Y" ]]; then
            echo "Installing intel-media-driver for newer Intel iGPU (6th gen or later)..."
            sudo dnf install -y intel-media-driver
        else
            echo "Installing libva-intel-driver for older Intel iGPU..."
            sudo dnf install -y libva-intel-driver
        fi

    elif [[ "$gpu_type" == "amd" || "$gpu_type" == "AMD" ]]; then
        echo "Installing AMD APU/GPU drivers..."

        # Install AMD drivers and enable better support
        sudo dnf install -y xorg-x11-drv-amdgpu
        
        # Swap Mesa VA and VDPAU drivers for better AMD support
        echo "Swapping Mesa VA and VDPAU drivers for better AMD support..."
        sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing
        sudo dnf swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing
        sudo dnf swap mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 --allowerasing
        sudo dnf swap mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686 --allowerasing

    else
        echo "Invalid GPU type. Please choose either 'intel' or 'amd'."
    fi
}

# Function to detect if the system is running in a VM
detect_vm() {
    echo "Checking if the system is running in a virtual machine..."
    
    # Check for the presence of VM indicators in lscpu output or dmesg
    if lscpu | grep -iE "hypervisor|vmware|virtualbox|qemu" &> /dev/null; then
        echo "The system appears to be running in a virtual machine."
        return 0
    else
        echo "The system does not appear to be in a virtual machine."
        return 1
    fi
}

# Main function
main() {
    # First, enable RPM Fusion repositories
    enable_rpmfusion

    # Detect if the system is running in a VM
    detect_vm
    is_vm=$?

    if [[ $is_vm -eq 0 ]]; then
        echo "Skipping hardware-accelerated codec installations since this is a virtual machine."
    fi

    # Remove Fedora's Flatpaks
    remove_fedora_flatpaks

    # Add Flathub repository
    add_flathub_repo

    # Check for Plasma Discover
    check_plasma_discover

    # Install multimedia codecs
    install_multimedia_codecs

    # Ask user for Intel iGPU or AMD APU/GPU information
    if [[ $is_vm -eq 1 ]]; then  # Only ask for GPU if it's not a VM
        ask_for_gpu
    fi

    echo "XDora setup complete!"
}

# Run the main function
main
