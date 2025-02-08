{
  description = "Raspberry Pi Audio Kiosk";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "flake-utils";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nixos-generators,
    }:
    let
      # Base configuration module
      baseModule =
        { pkgs, ... }:
        let
          wifi_ssid = builtins.getEnv "WIFI_SSID";
          wifi_key = builtins.getEnv "WIFI_KEY";
        in
        {
          networking.wireless =
            if wifi_ssid != "" then
              {
                enable = true;
                userControlled.enable = true;
                networks."${wifi_ssid}" = {
                  psk = wifi_key;
                };
              }
            else
              { };

          environment.systemPackages = with pkgs; [
            mpv
            (python3.withPackages (
              ps: with ps; [
                peewee
                python-mpv-jsonipc
              ]
            ))
          ];

          systemd.services = {
            mpv-daemon = {
              description = "MPV Daemon";
              wantedBy = [ "multi-user.target" ];
              serviceConfig.Type = "forking";
              execStart = "${pkgs.mpv}/bin/mpv --no-video --daemonize --input-ipc-server=/tmp/mpv-socket";
            };

            kiosk-controller = {
              description = "Audio Kiosk Controller";
              wants = [ "mpv-daemon.service" ];
              after = [ "mpv-daemon.service" ];
              serviceConfig.Type = "simple";
              execStart = "${pkgs.python3}/bin/python ${./kiosk.py}";
              restart = "always";
            };
          };

          hardware.pulseaudio.enable = true;
        };

      # Raspberry Pi specific module
      raspberryPiModule = {
        boot.loader.grub.enable = false;
        boot.loader.generic-extlinux-compatible.enable = nixpkgs.lib.mkForce true;

        fileSystems."/" = {
          device = "/dev/disk/by-label/NIXOS_SD";
          fsType = nixpkgs.lib.mkForce "f2fs";
          autoResize = true;
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
            chmod +x ${./dev-wrapper.sh}
            echo "Run './dev-wrapper.sh' to start both MPV and the kiosk"
          '';
        };

        packages = {
          qemu_vm = nixos-generators.nixosGenerate {
            inherit system;
            format = "vm";
            modules = [
              baseModule
              qemuModule
              (
                { ... }:
                {
                  virtualisation = {
                    cores = 4;
                    memorySize = 2048;
                    qemu.options = [ "-cpu max" ];
                  };
                }
              )
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
