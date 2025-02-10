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
          RUNTIME_DIR = "/run/user/1000";
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

          # Add global session variables
          environment.sessionVariables = {
            XDG_RUNTIME_DIR = RUNTIME_DIR;
          };

          networking.wireless = {
            enable = true;
            networks."${
              if wifi_ssid != "" then wifi_ssid else "$(. /etc/wifi-credentials && echo $WIFI_SSID)"
            }" =
              {
                psk = if wifi_key != "" then wifi_key else "$(. /etc/wifi-credentials && echo $WIFI_KEY)";
              };
          };

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

          security.sudo = {
            enable = true;
            wheelNeedsPassword = false;
          };

          services.openssh.enable = true;

          system.stateVersion = "25.05";

          systemd.services = {
            mpv-daemon = {
              description = "MPV Daemon";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.lib.getExe pkgs.mpv} --no-video --idle --input-ipc-server=${RUNTIME_DIR}/mpv.sock";
                RuntimeDirectory = "user/1000";
                RuntimeDirectoryMode = "0755";
                Type = "idle";
                User = "nixos";
              };
            };

            "getty@tty1" = {
              enable = true;
              after = [ "mpv-daemon.service" ];
              requires = [ "mpv-daemon.service" ];
              overrideStrategy = "asDropin";
              serviceConfig = {
                ExecStart = "${pkgs.lib.getExe pythonEnv} ${controller}";
                StandardInput = "tty";
                StandardOutput = "tty";
                TTYPath = "/dev/tty1";
                TTYReset = true;
                TTYVHangup = true;
                Type = "idle";
                User = "nixos";
                WorkingDirectory = "/home/nixos";
              };
            };
          };

          users = {
            users.nixos = {
              extraGroups = [ "wheel" ];
              isNormalUser = true;
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv4SpIhHJqtRaYBRQOin4PTDUxRwo7ozoQHTUFjMGLW avunu@AvunuCentral"
              ];
              password = "nixos";
              shell = pkgs.bash;
              uid = 1000;
            };
          };
        };

      # Raspberry Pi specific module
      raspberryPiModule = {
        # target raspberry pi 4
        raspberry-pi-nix = {
          board = "bcm2711";
          libcamera-overlay = false;
        };
        # boot.loader.grub.enable = false;
        # boot.loader.generic-extlinux-compatible.enable = nixpkgs.lib.mkForce true;

        # use tmpfs to reduce SD card wear
        fileSystems = {
          "/" = {
            device = "/dev/disk/by-label/NIXOS_SD";
            fsType = nixpkgs.lib.mkForce "ext4";
            autoResize = true;
          };
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

        # Disable things we don't need
        hardware.bluetooth.enable = false;

        system.autoUpgrade = {
          allowReboot = false;
          enable = true;
          flake = "github:batonac/audio-kiosk#raspberryPi";
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
    (flake-utils.lib.eachDefaultSystem (
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

        packages.${system} = {
          vm = nixos-generators.nixosGenerate {
            inherit system;
            format = "vm";
            modules = [
              baseModule
              {
                virtualisation = {
                  cores = 4;
                  memorySize = 2048;
                  diskSize = 8192; # 8GB disk
                };
              }
            ];
          };
        };
      }
    )) // {
      nixosConfigurations = {
        raspberryPi = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            baseModule
            raspberryPiModule
            raspberry-pi-nix.nixosModules.raspberry-pi
          ];
        };
      };
      
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
