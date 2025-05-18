{
  description = "Doom2D flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-bundle = {
      url = "github:nix-community/nix-bundle";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    osxcross = {
      url = "github:polybluez/osxcross/framework";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    DF-Assets = {
      url = "git+https://github.com/Doom2D/DF-Assets";
      flake = false;
    };
    Doom2D-Forever = {
      url = "git+file:/home/nixos/Git/Doom2D-Forever?submodules=1";
      flake = false;
    };
    d2df-editor = {
      url = "git+https://github.com/Doom2D/Doom2D-Forever?submodules=1&ref=d2df-editor.git";
      flake = false;
    };
    d2df-distro-content = {
      url = "https://doom2d.org/doom2d_forever/latest/df_distro_content.rar";
      flake = false;
    };
    d2df-distro-soundfont = {
      url = "https://doom2d.org/doom2d_forever/latest/df_midi_bank.rar";
      flake = false;
    };
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-stable,
    flake-utils,
    nix-github-actions,
    nix-bundle,
    osxcross,
    DF-Assets,
    Doom2D-Forever,
    d2df-editor,
    d2df-distro-content,
    d2df-distro-soundfont,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config = {
          android_sdk.accept_license = true;
          allowUnfree = true;
          allowUnsupportedSystem = true;
        };
        overlays = [
          (final: prev: {
            pathsFromGraph = let oldPkgs = import inputs.nixpkgs-stable {inherit (final) system;}; in oldPkgs.pathsFromGraph;
          })
          (final: prev: {
            wadcvt = final.callPackage d2dfPkgs.wadcvt {
              inherit Doom2D-Forever;
            };
            dfwad = final.callPackage d2dfPkgs.dfwad {
              src = pins.dfwad.src;
            };
            cctools = osxcross.packages.${system}.cctools;
            macdylibbundler = prev.macdylibbundler.overrideAttrs (prevAttrs: let
              otool = final.writeShellScriptBin "otool" ''
                ${final.cctools}/bin/x86_64-apple-darwin20.4-otool $@
              '';
              install_name_tool = final.writeShellScriptBin "install_name_tool" ''
                ${final.cctools}/bin/x86_64-apple-darwin20.4-install_name_tool $@
              '';
            in {
              postInstall = ''
                wrapProgram $out/bin/dylibbundler \
                  --prefix PATH ":" "${otool}/bin" \
                  --prefix PATH ":" "${install_name_tool}/bin"
              '';
            });
          })
        ];
      };
      lib = pkgs.lib;
      fpcPkgs = import ./fpc {
        inherit (pkgs) callPackage fetchgit stdenv;
        inherit pkgs;
        inherit lib pins;
      };
      d2dfPkgs = import ./game;
      bundles = import ./game/bundle {
        inherit (pkgs) callPackage;
      };
      assetsLib = import ./game/assets {
        inherit (pkgs) callPackage;
      };

      pins = import ./pins/generated.nix {
        inherit (pkgs) fetchgit fetchurl fetchFromGitHub dockerTools;
      };
    in {
      buildInputs = {
        inherit nix-bundle;
      };
      bundlers = let
        nix-bundle-fun = {
          drv,
          programPath ? pkgs.lib.getExe drv,
        }: let
          nixpkgs = inputs.nixpkgs-stable.legacyPackages.${system};
          nix-bundle = import inputs.nix-bundle {inherit nixpkgs;};
          nix-user-chroot = nix-bundle.nix-user-chroot.overrideAttrs (finalAttrs: prevAttrs: {
            buildInputs = [pkgs.stdenv.cc.cc.lib];
            postFixup =
              prevAttrs.postFixup
              + ''
                patchelf --add-needed ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 \
                  $out/bin/nix-user-chroot
              '';
          });
          script = nixpkgs.writeScript "startup" ''
            #!/bin/sh
            .${lib.trace "${nix-user-chroot}" nix-user-chroot}/bin/nix-user-chroot -n ./nix -- ${programPath} "$@"
          '';
        in
          nix-bundle.makebootstrap {
            drvToBundle = drv;
            targets = [script];
            startup = ".${builtins.unsafeDiscardStringContext script} '\"$@\"'";
          };
      in {
        default = inputs.self.bundlers.${system}.nix-bundle;
        nix-bundle = drv: nix-bundle-fun {inherit drv;};
        nix2appimage = import "${nix-bundle}/appimage-top.nix" {nixpkgs' = lib.recursiveUpdate nixpkgs {inherit (nixpkgs-stable) pathsFromGraph; };};
      };
      dfInputs = {
        inherit Doom2D-Forever d2df-editor DF-Assets d2df-distro-content d2df-distro-soundfont;
      };

      osxcross = osxcross;

      checks = let
        nativeArches = lib.removeAttrs self.legacyPackages.${system} ["android" "universal"];
      in
        lib.mapAttrs (n: v: v.drv) (lib.foldl (acc: x: acc // x) {} (lib.map (x:
          lib.mapAttrs (n: v: {
            inherit (v) defines;
            drv = v.drv.overrideAttrs {
              pname = n;
              name = n;
            };
          }) (x.executables)) (lib.attrValues nativeArches)));

      assetsLib = assetsLib;

      executables = import ./packages/executables.nix {
        inherit pkgs lib fpcPkgs d2dfPkgs;
        inherit Doom2D-Forever d2df-editor;
        inherit pins osxcross;
      };

      assets = import ./packages/assets.nix {
        inherit lib;
        inherit (pkgs) callPackage stdenv writeText dfwad;
        inherit DF-Assets d2df-editor;
        inherit (d2dfPkgs) buildWad;
        inherit (assetsLib) mkAssetsPath;
      };

      inherit pins fpcPkgs d2dfPkgs;

      nixosModules = import ./nixos/modules;

      legacyPackages = let
        cross = import ./packages {
          inherit lib;
          inherit pins;
          inherit (pkgs) callPackage;
          inherit (assetsLib) androidRoot androidIcons mkAndroidManifest macOsIcns macOsPlist;
          defaultAssetsPath = self.assets.${system}.defaultAssetsPath;
          inherit (bundles) mkExecutablePath mkZip mkPath mkApple mkLicenses mkGamePath mkAndroidApk;
          executablesAttrs = self.executables.${system};
          d2df-distro-content = inputs.d2df-distro-content;
          d2df-distro-soundfont = inputs.d2df-distro-soundfont;
        };
        aux = {
          doom2d-forever-master-server = pkgs.callPackage d2dfPkgs.doom2d-forever-master-server {};
          doom2d-multiplayer-game-data = pkgs.callPackage d2dfPkgs.doom2d-multiplayer-game-data {};
          doom2df-base = pkgs.callPackage d2dfPkgs.doom2df-base {};
        };
      in
        lib.recursiveUpdate cross aux;

      packages = {
        inherit (pkgs) wadcvt dfwad;
      };

      forPrebuild = let
        arches = ["mingw32" "mingw64" "x86_64-apple-darwin" "arm64-apple-darwin" "armeabi-v7a-linux-android" "arm64-v8a-linux-android"];
      in
        lib.foldl (acc: cur: let
          filtered = lib.removeAttrs self.legacyPackages.x86_64-linux.${cur}.__archPkgs ["doom2d" "infoAttrs"];
          drvs = lib.filter (x: !builtins.isNull x && (x ? name)) (lib.attrValues filtered);
        in
          acc
          // {
            "${cur}" =
              pkgs.closureInfo {rootPaths = [(pkgs.linkFarmFromDrvs "cache-${cur}" drvs) pkgs.dfwad];};
          }) {}
        arches;

      devShells = {
        default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            alejandra
            nixd
          ];
        };

        ciDefault = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            bash
            jq
            _7zz
            zstd
            git
            findutils
            dos2unix
            coreutils
            unrar-wrapper
            rar
            coreutils-full
            cdrkit
          ];
        };

        android = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            openjdk
            openssl
            rar
            _7zz
            (pkgs.writeShellScriptBin "zipalign" "${self.legacyPackages.${system}.arm64-v8a-linux-android.__archPkgs.androidSdk}/libexec/android-sdk/build-tools/35.0.0/zipalign $@")
            (pkgs.writeShellScriptBin "apksigner" "${self.legacyPackages.${system}.arm64-v8a-linux-android.__archPkgs.androidSdk}/libexec/android-sdk/build-tools/35.0.0/apksigner $@")
          ];
        };
      };
    });
}
