#!/usr/bin/env bash

# Load environment variables if .env exists
if [ -f .env ]; then
    echo "Loading environment variables from .env"
    set -o allexport
    source .env
    set +o allexport
fi

# Print menu
echo "Select build target:"
echo "1) Development shell"
echo "2) Raspberry Pi image"
echo "3) QEMU VM image"
echo
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        echo "Starting development shell..."
        nix develop
        ;;
    2)
        echo "Building Raspberry Pi image..."
        nix build .#packages.aarch64-linux.sdImage --impure
        echo "Image built at: ./result/sd-image/*.img"
        ;;
    3)
        echo "Building QEMU VM image..."
        nix build .#packages.$(nix eval --impure --expr builtins.currentSystem --raw).qemu_vm --impure
        echo "Run VM with: ./result/bin/run-*-vm"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
