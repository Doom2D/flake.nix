{
  stdenv,
  executables,
  assets,
  licenses ? null,
  lib,
  _7zz,
  lndir,
  makeDesktopItem,
  writeTextFile,
  closureInfo,
  copyDesktopItems,
}: let
  first = (lib.head (lib.attrsToList executables.meta.arches)).value;
  desktopItem = makeDesktopItem {
    name = "Doom2DF";
    desktopName = "Doom2D Forever";
    exec = "Doom2DF";
    genericName = "Platformer";
    terminal = false;
    icon = "Doom2DF";
    extraConfig = {
      "Version" = "1.0";
    };
  };
  appImageLibDirs = [
    # Distro library paths
    "/usr/lib/x86_64-linux-gnu"  # Debian, Ubuntu
    "/usr/lib/x86_64-linux-gnu/mesa"
    "/usr/lib"                # Arch, Alpine
    "/usr/lib64"              # Fedora
    "/usr/lib/i386-linux-gnu"
    "/usr/lib32"
    "/lib"
    "/lib/i386-linux-gnu"
    "/lib/x86_64-linux-gnu"
    "/lib32"
    "/lib64"
    "/usr/lib/xorg/modules"
    "/usr/lib/xorg/modules/extensions"
  ];
  wrapper = exe: let system = "x86_64-linux-gnu"; appImageLibDirs = [
    # Distro library paths
    "/usr/lib/${system}-gnu"  # Debian, Ubuntu
    "/usr/lib/x86_64-linux-gnu/mesa"
    "/usr/lib"                # Arch, Alpine
    "/usr/lib64"              # Fedora
    "/usr/lib/i386-linux-gnu"
    "/usr/lib32"
    "/lib"
    "/lib/i386-linux-gnu"
    "/lib/x86_64-linux-gnu"
    "/lib32"
    "/lib64"
    "/usr/lib/xorg/modules"
    "/usr/lib/xorg/modules/extensions"
  ]; in (writeTextFile {
    name = "Doom2DF";
    executable = true;
    text = ''#!/bin/sh
      export LD_LIBRARY_PATH=${lib.concatStringsSep ":" appImageLibDirs}
      echo hehe
      ${exe} $@
    '';});
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "d2df-fhs-path";
    version = "0.667";

    buildInputs = [_7zz lndir];

    nativeBuildInputs = [first.doom2df.buildInputs first.doom2df executables];

    src = null;

    dontUnpack = true;
    dontStrip = true;
    dontPatchELF = true;
    dontFixup = true;
    dontShrink = true;

    installPhase = let info = closureInfo {
      rootPaths = [executables];
    }; in 
      ''
        mkdir -p $out/bin $out/share/doom2df $out/share/applications $out/share/icons/hicolor/256x256/apps/
        touch $out/share/icons/hicolor/256x256/apps/Doom2DF.png
        cp ${executables}/Doom2DF $out/bin/Doom2DF
        chmod 777 $out/bin/Doom2DF
        ${let target = "$out/bin/Doom2DF"; mkPatchelf = x: "patchelf ${target} --add-rpath ${x}"; cmds = lib.map mkPatchelf appImageLibDirs; in lib.traceVal (lib.concatStringsSep "\n" cmds)}
        patchelf --add-needed libGL.so.1 $out/bin/Doom2DF
        cat ${info}/store-paths
        lndir ${desktopItem} $out
      ''
      + lib.optionalString (!builtins.isNull licenses) ''
        mkdir -p $out/share/doom2df/licenses
        lndir ${lib.trace "${licenses}" licenses}/ $out/share/doom2df/licenses
      '';

    meta.mainProgram = "Doom2DF";
  })
