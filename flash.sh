#!/usr/bin/env bash

set -e

# Function to list removable devices
list_devices() {
    local devices=()
    while read -r line; do
        if [[ $line =~ removable ]]; then
            local dev=$(echo "$line" | cut -d' ' -f1)
            local size=$(lsblk -n -o SIZE "$dev" | head -1)
            local model=$(lsblk -n -o MODEL "$dev" | head -1)
            echo "${dev##*/}) $(printf "%-15s" "$model") Size: $size"
        fi
    done < <(lsblk -p -d -o NAME,RM,SIZE,MODEL | grep "1[[:space:]]")
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Please do not run this script as root"
    exit 1
fi

# Check if image exists
if [ ! -d "./result/sd-image" ]; then
    echo "Error: No SD image found in ./result/sd-image/"
    echo "Please build the image first using ./build.sh"
    exit 1
fi

# List available devices
echo "Available devices:"
echo
list_devices
echo

# Get user selection
read -p "Enter device name (e.g., sdb): " device

# Validate device exists and is removable
if ! lsblk -d -o NAME,RM | grep -q "^${device}.*1[[:space:]]*$"; then
    echo "Error: Invalid or non-removable device selected"
    exit 1
fi

# Show confirmation with warning
echo
echo "WARNING: This will ERASE ALL DATA on /dev/${device}"
echo "Device details:"
lsblk -o NAME,SIZE,MODEL "/dev/$device"
echo
read -p "Are you sure you want to continue? (y/N) " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 1
fi

# Flash the image
echo "Flashing image to /dev/${device}..."
zstdcat ./result/sd-image/*.img.zst | sudo dd of="/dev/${device}" bs=4M status=progress conv=fsync

echo "Flash complete!"
