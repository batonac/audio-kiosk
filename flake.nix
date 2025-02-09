{
  description = "Raspberry Pi Audio Kiosk";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "flake-utils";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    raspberry-pi-nix.url = "github:nix-community/raspberry-pi-nix";
  };

  outputs =
    {
      self,
      flake-utils,
      nixos-generators,
      nixpkgs,
      raspberry-pi-nix,
    }:
    let
      # Base configuration module
      baseModule =
        { pkgs, ... }:
        let
          wifi_ssid = builtins.getEnv "WIFI_SSID";
          wifi_key = builtins.getEnv "WIFI_KEY";
          wifiEnvFile = pkgs.writeText "wifi-credentials" ''
            WIFI_SSID="${wifi_ssid}"
            WIFI_KEY="${wifi_key}"
          '';
          pythonEnv = pkgs.python3.withPackages (
            ps: with ps; [
              peewee
              python-mpv-jsonipc
            ]
          );
          controller = pkgs.writeText "kiosk.py" (builtins.readFile ./kiosk.py);

        in
        {
          environment.etc."wifi-credentials".source = wifiEnvFile;

          networking.wireless =
            let
              # Source credentials from the persistent file
              persistentWifiSsid = "$(. /etc/wifi-credentials && echo $WIFI_SSID)";
              persistentWifiKey = "$(. /etc/wifi-credentials && echo $WIFI_KEY)";
            in
            if wifi_ssid != "" then
              {
                enable = true;
                userControlled.enable = true;
                networks."${persistentWifiSsid}" = {
                  psk = persistentWifiKey;
                };
              }
            else
              { };

          nix = {
            gc = {
              automatic = true;
              dates = "weekly";
              options = "--delete-older-than 7d";
            };
            settings = {
              experimental-features = [
                "nix-command"
                "flakes"
              ];
              substituters = [
                "https://cache.nixos.org?priority=40"
                "https://nix-community.cachix.org?priority=41"
              ];
              trusted-public-keys = [
                "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              ];
              trusted-users = [
                "root"
                "nixos"
                "@wheel"
              ];
            };
          };

          systemd.services = {
            mpv-daemon = {
              unitConfig = {
                Description = "MPV Daemon";
              };
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "forking";
                ExecStart = "${pkgs.mpv}/bin/mpv --no-video --daemonize --input-ipc-server=/tmp/mpv-socket";
              };
            };

            kiosk-controller = {
              unitConfig = {
                Description = "Audio Kiosk Controller";
              };
              wants = [ "mpv-daemon.service" ];
              after = [ "mpv-daemon.service" ];
              serviceConfig = {
                Environment = "HOME=/home/nixos";
                ExecStart = "${pkgs.lib.getExe pythonEnv} ${controller}";
                Restart = "always";
                RestartSec = "5";
                Type = "simple";
                User = "nixos";
                WorkingDirectory = "/home/nixos";
              };
            };
          };

          users = {
            users.nixos = {
              isNormalUser = true;
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv4SpIhHJqtRaYBRQOin4PTDUxRwo7ozoQHTUFjMGLW avunu@AvunuCentral"
              ];
              shell = pkgs.bash;
            };
          };
        };

      # Raspberry Pi specific module
      raspberryPiModule = {
        # target raspberry pi 4
        # raspberry-pi-nix.board = "bcm2711";
        # boot.loader.grub.enable = false;
        # boot.loader.generic-extlinux-compatible.enable = nixpkgs.lib.mkForce true;

        # fileSystems."/" = {
        #   device = "/dev/disk/by-label/NIXOS_SD";
        #   fsType = nixpkgs.lib.mkForce "ext4";
        #   autoResize = true;
        # };

        # use tmpfs to reduce SD card wear
        fileSystems = {
          "/tmp" = {
            device = "tmpfs";
            fsType = "tmpfs";
            options = [ "mode=1777" ];
          };
          "/var" = {
            device = "tmpfs";
            fsType = "tmpfs";
            options = [ "mode=0755" ];
          };
        };

        system.autoUpgrade = {
          allowReboot = false;
          enable = true;
          flake = "github:batonac/audio-kiosk#nixos";
          flags = [ "--impure" ];
        };
      };

      # QEMU specific module
      qemuModule = {
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        fileSystems."/" = {
          device = "/dev/vda1";
          fsType = "ext4";
        };
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        pythonEnv = pkgs.python3.withPackages (
          ps: with ps; [
            peewee
            python-mpv-jsonipc
          ]
        );
      in
      {
        devShells.default = pkgs.mkShell {

          buildInputs = with pkgs; [
            pythonEnv
            mpv
            bash
          ];

          shellHook = ''
            export PYTHONPATH=${pythonEnv}/${pythonEnv.sitePackages}
            # Make the wrapper executable
            echo "Run 'bash dev-wrapper.sh' to start both MPV and the kiosk"
          '';
        };

        nixosConfigurations = {
          raspberryPi = {
            system = "aarch64-linux";
            config = {
              imports = [
                baseModule
                raspberryPiModule
                raspberry-pi-nix.nixosModules.raspberry-pi
              ];
            };
          };

          # Add QEMU configuration
          qemu = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              baseModule
              qemuModule
              {
                virtualisation = {
                  cores = 4;
                  memorySize = 2048;
                  qemu.options = [ "-cpu max" ];
                };
              }
            ];
          };
        };

        # Simplified packages section
        packages = {
          default = self.packages.${system}.qemu_vm;
          qemu_vm = nixos-generators.nixosGenerate {
            inherit system;
            format = "vm";
            modules = [
              baseModule
              qemuModule
              {
                virtualisation = {
                  cores = 4;
                  memorySize = 2048;
                  qemu.options = [ "-cpu max" ];
                };
              }
            ];
          };
        };
      }
    )
    // {
      packages.aarch64-linux = {
        sdImage = nixos-generators.nixosGenerate {
          system = "aarch64-linux";
          format = "sd-aarch64";
          modules = [
            baseModule
            raspberryPiModule
          ];
        };
      };
    };
}
