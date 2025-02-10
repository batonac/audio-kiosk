#!/usr/bin/env bash

set -e

# Function to list removable devices and store them in an array
list_devices() {
    declare -ga devices=()  # Make array global
    local idx=1

    # Clear existing array
    devices=()

    # Find SD card devices (mmcblk*)
    while read -r dev; do
        if [ -n "$dev" ]; then
            size=$(lsblk -n -o SIZE "$dev" | head -1)
            model=$(lsblk -n -o MODEL "$dev" | head -1)
            if [ -z "$model" ]; then model="SD/MMC Card"; fi
            echo "$idx) $(printf "%-15s" "$model") Size: $size (${dev##*/})"
            devices+=("${dev##*/}")
            ((idx++))
        fi
    done < <(find /dev -maxdepth 1 -name "mmcblk[0-9]" 2>/dev/null)

    # Find USB/removable devices (sd*)
    while read -r line; do
        if [[ $line =~ removable ]]; then
            local dev=$(echo "$line" | cut -d' ' -f1)
            local size=$(lsblk -n -o SIZE "$dev" | head -1)
            local model=$(lsblk -n -o MODEL "$dev" | head -1)
            echo "$idx) $(printf "%-15s" "$model") Size: $size (${dev##*/})"
            devices+=("${dev##*/}")
            ((idx++))
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

# List available devices and get selection
echo "Available devices:"
echo
list_devices

device_count=${#devices[@]}
if [ $device_count -eq 0 ]; then
    echo "No removable devices found!"
    exit 1
fi

echo
echo "Select a device (1-$device_count):"
read -r -p "> " choice

# Validate input
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$device_count" ]; then
    echo "Error: Invalid selection"
    exit 1
fi

device="${devices[$((choice-1))]}"

# Show confirmation with warning
echo
echo "WARNING: This will ERASE ALL DATA on /dev/${device}"
echo "Device details:"
lsblk -o NAME,SIZE,MODEL "/dev/$device"
echo
read -r -p "Are you sure you want to continue? (y/N) " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 1
fi

# Flash the image
echo "Flashing image to /dev/${device}..."
zstdcat ./result/sd-image/*.img.zst | sudo dd of="/dev/${device}" bs=4M status=progress conv=fsync

echo "Flash complete!"
