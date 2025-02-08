# Audio Kiosk

A Raspberry Pi based audio kiosk system using MPV and NixOS.

## Setup

1. Clone this repository
2. Copy `.env.example` to `.env` and configure your WiFi credentials:
   ```bash
   cp .env.example .env
   ```
3. Edit `.env` with your network details

## Building

Use the build script to create your desired output:
```bash
./build.sh
```

The script will offer three options:
1. Development shell
2. Raspberry Pi SD image
3. QEMU VM image

## Development

- Use the dev shell for local development and testing
- QEMU VM can be used to test the full system
- The Pi image can be flashed to an SD card

## Network Configuration

WiFi settings are configured at build time through environment variables. Make sure your `.env` file is properly configured before building the Pi or QEMU images.
