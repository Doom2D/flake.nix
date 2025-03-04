{
  pkgs,
  lib,
  pins,
  osxcross,
  fpcPkgs,
  d2dfPkgs,
  Doom2D-Forever,
  d2df-editor,
}: let
  android = (import ../cross/android) {
    inherit pkgs lib pins;
  };
  mingw = (import ../cross/mingw) {
    inherit pkgs lib pins;
  };
  mac = (import ../cross/mac) {
    inherit pkgs lib pins osxcross;
  };
  universal = rec {
    fpc-trunk = fpcPkgs.fpc-trunk;
    fpc-3_2_2 = fpcPkgs.fpc-3_2_2;
    fpc-release = fpc-3_2_2;
    fpc = fpc-trunk;

    lazarus-trunk = fpcPkgs.lazarus-trunk.overrideAttrs {
      fpc = fpc;
    };
    lazarus-3_6 = fpcPkgs.lazarus-3_6.overrideAttrs {
      fpc = fpc;
    };
    lazarus = lazarus-trunk;
  };
  f = crossPkgs: let
    archsAttrs = lib.mapAttrs (arch: archAttrs: archAttrs.infoAttrs.fpcAttrs) crossPkgs;
    fromCrossPkgsAttrs = arch: archAttrs: let
      fpcCross-trunk = fpcPkgs.fpcCross-trunk.override {
        fpcArchAttrs = archAttrs.infoAttrs.fpcAttrs;
        archName = arch;
      };
      fpcCross-3_2_2 = fpcPkgs.fpcCross-3_2_2.override {
        fpcArchAttrs = archAttrs.infoAttrs.fpcAttrs;
        archName = arch;
      };
      fpcCross = fpcCross-trunk;
      fpcWrapper = fpc: fpcCross:
        pkgs.callPackage fpcPkgs.fpcWrapper rec {
          inherit fpcCross;
          fpcAttrs = let
            prevFpcAttrs = archAttrs.infoAttrs.fpcAttrs;
          in
            prevFpcAttrs
            // {
              toolchainPaths =
                prevFpcAttrs.toolchainPaths
                ++ [
                  "${pkgs.writeShellScriptBin
                    "${prevFpcAttrs.makeArgs.CPU_TARGET}-${prevFpcAttrs.makeArgs.OS_TARGET}-fpcres"
                    "${fpc}/bin/fpcres $@"}/bin"
                ];
            };
        };
      gamePkgs = rec {
        fpc = fpc-trunk;
        fpc-3_2_2 = fpcWrapper universal.fpc-3_2_2 fpcCross-3_2_2;
        fpc-trunk = fpcWrapper universal.fpc-trunk fpcCross-trunk;
        lazarus-trunk =
          if (archAttrs.infoAttrs.fpcAttrs.lazarusExists)
          then
            (pkgs.callPackage fpcPkgs.lazarusWrapper {
              # FIXME
              # lazarus doesn't compile editor with trunk fpc
              fpc = fpc;
              fpcAttrs = archAttrs.infoAttrs.fpcAttrs;
              lazarus = universal.lazarus-trunk;
            })
          else null;
        lazarus-3_6 =
          if (archAttrs.infoAttrs.fpcAttrs.lazarusExists)
          then
            (pkgs.callPackage fpcPkgs.lazarusWrapper {
              # FIXME
              # lazarus doesn't compile editor with trunk fpc
              fpc = fpc-3_2_2;
              fpcAttrs = archAttrs.infoAttrs.fpcAttrs;
              lazarus = universal.lazarus-3_6;
            })
          else null;
        lazarus = lazarus-3_6;
        editor =
          if (archAttrs.infoAttrs.fpcAttrs.lazarusExists)
          then
            (pkgs.callPackage d2dfPkgs.editor {
              inherit d2df-editor;
              lazarus = lazarus;
            })
          else null;
        doom2d = pkgs.callPackage d2dfPkgs.doom2df-base {
          inherit Doom2D-Forever;
          inherit fpc;
          isDarwin = lib.hasSuffix "darwin" arch;
          inherit
            (archAttrs)
            enet
            SDL
            SDL_mixer
            SDL2
            SDL2_mixer
            openal
            libvorbis
            libogg
            libxmp
            libmpg123
            libopus
            opusfile
            game-music-emu
            miniupnpc
            fluidsynth
            libmodplug
            fmodex
            ;
        };
      };
    in
      lib.recursiveUpdate archAttrs gamePkgs;
  in
    (lib.mapAttrs fromCrossPkgsAttrs crossPkgs) // {universal = universal;};
in
  f (android // mingw // mac)
