{
  description = "Doom2D flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-github-actions.url = "github:nix-community/nix-github-actions";
    osxcross = {
      url = "github:polybluez/osxcross/framework";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    DF-res = {
      url = "github:Doom2D/DF-Res";
      flake = false;
    };
    Doom2D-Forever = {
      url = "git+https://github.com/Doom2D/Doom2D-Forever?submodules=1";
      flake = false;
    };
    d2df-editor = {
      url = "github:Doom2D/Doom2D-Forever/d2df-editor.git";
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
    flake-utils,
    nix-github-actions,
    osxcross,
    DF-res,
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
            wadcvt = final.callPackage d2dfPkgs.wadcvt {
              inherit Doom2D-Forever;
            };
            dfwad = final.callPackage d2dfPkgs.dfwad {
              src = pins.dfwad.src;
            };
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
      dfInputs = {
        inherit Doom2D-Forever d2df-editor DF-res d2df-distro-content d2df-distro-soundfont;
      };

      osxcross = osxcross;

      checks = let
        nativeArches = lib.removeAttrs self.legacyPackages.${system} ["android" "universal"];
      in
        lib.mapAttrs (n: v: v.drv) (lib.foldl (acc: x: acc // x) {} (lib.map (x: x.executables) (lib.attrValues nativeArches)));

      assetsLib = assetsLib;

      executables = import ./packages/executables.nix {
        inherit pkgs lib fpcPkgs d2dfPkgs;
        inherit Doom2D-Forever d2df-editor;
        inherit pins osxcross;
      };

      assets = import ./packages/assets.nix {
        inherit lib;
        inherit (pkgs) callPackage stdenv writeText dfwad;
        inherit DF-res d2df-editor;
        inherit (d2dfPkgs) buildWad;
        inherit (assetsLib) mkAssetsPath;
      };

      inherit pins;

      legacyPackages = import ./packages {
        inherit lib;
        inherit pins;
        inherit (pkgs) callPackage;
        inherit (assetsLib) androidRoot androidIcons mkAndroidManifest;
        defaultAssetsPath = self.assets.${system}.defaultAssetsPath;
        inherit (bundles) mkExecutablePath mkGamePath mkAndroidApk;
        executablesAttrs = self.executables.${system};
      };

      packages = {
        inherit (pkgs) wadcvt dfwad;
      };

      forPrebuild = let
        arches = ["mingw32" "mingw64" "x86_64-apple-darwin" "arm64-apple-darwin" "android"];
      in
        pkgs.linkFarmFromDrvs "cache" (lib.foldl (a: b:
          ([
            (self.legacyPackages.x86_64-linux.${b}.bundles.default.overrideAttrs
              (final: {pname = b;}))
          ])
          ++ a) []
        arches);

      devShells = {
        default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            bash
            alejandra
            nixd
            jq
            _7zz
            git
            findutils
            dos2unix
            libfaketime
            coreutils
            openjdk
            npins
            unrar-wrapper
            rar
            openssl
            coreutils-full
            (pkgs.writeShellScriptBin "zipalign" "${self.legacyPackages.${system}.arm64-v8a-linux-android.__archPkgs.androidSdk}/libexec/android-sdk/build-tools/35.0.0/zipalign $@")
            (pkgs.writeShellScriptBin "apksigner" "${self.legacyPackages.${system}.arm64-v8a-linux-android.__archPkgs.androidSdk}/libexec/android-sdk/build-tools/35.0.0/apksigner $@")
            cdrkit
          ];
        };
      };
    });
}
