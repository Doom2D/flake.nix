{
  callPackage,
  fetchgit,
  stdenv,
  lib,
  pins,
  pkgs,
}: let
  fpcDrv = {
    lib,
    stdenv,
    gawk,
    fpc,
    glibc,
    binutils,
  }: let
    default = ["NOGDB=1" "FPC=\"${fpc}/bin/fpc\"" "PP=\"${fpc}/bin/fpc\"" "INSTALL_PREFIX=$out"];
  in
    stdenv.mkDerivation (finalAttrs: rec {
      version = "3.3.1";
      pname = "fpc";
      src = pins.fpc.src;

      nativeBuildInputs = [binutils gawk fpc];
      inherit glibc;

      patches = [
        ./mark-paths-trunk.patch
      ];

      postPatch = ''
        # substitute the markers set by the mark-paths patch
        substituteInPlace compiler/systems/t_linux.pas --subst-var-by dynlinker-prefix "${glibc}"
        substituteInPlace compiler/systems/t_linux.pas --subst-var-by syslibpath "${glibc}/lib"
        # Replace the `codesign --remove-signature` command with a custom script, since `codesign` is not available
        # in nixpkgs
        # Remove the -no_uuid strip flag which does not work on llvm-strip, only
        # Apple strip.
        substituteInPlace compiler/Makefile \
          --replace \
            "\$(CODESIGN) --remove-signature" \
            "${fpc}/remove-signature.sh}" \
          --replace "ifneq (\$(CODESIGN),)" "ifeq (\$(OS_TARGET), darwin)" \
          --replace "-no_uuid" ""
      '';

      buildPhase = ''
        make all ${lib.concatStringsSep " " default}
      '';

      installPhase =
        ''
          make install ${lib.concatStringsSep " " default}
        ''
        + ''
          for i in $out/lib/fpc/*/ppc*; do
            ln -fs $i $out/bin/$(basename $i)
          done

          mkdir -p $out/lib/fpc/etc/
          $out/lib/fpc/*/samplecfg $out/lib/fpc/${version} $out/lib/fpc/etc/

          # Generate config files in /etc since on darwin, ppc* does not follow symlinks
          # to resolve the location of /etc
          mkdir -p $out/etc
          $out/lib/fpc/*/samplecfg $out/lib/fpc/${version} $out/etc
        '';

      meta = with lib; {
        description = "Free Pascal Compiler from a source distribution";
        homepage = "https://www.freepascal.org";
        maintainers = [maintainers.raskin];
        license = with licenses; [gpl2 lgpl2];
        platforms = platforms.unix;
      };
    });

  fpcCrossDrv = {
    lib,
    stdenv,
    gawk,
    fpc,
    fpcArchAttrs ? {},
    archName ? "",
    binutils,
    findutils,
  }: let
    default = ["NOGDB=1" "FPC=\"${fpc}/bin/fpc\"" "PP=\"${fpc}/bin/fpc\"" "INSTALL_PREFIX=$out"];
    path = lib.concatStringsSep ":" fpcArchAttrs.toolchainPaths;
    makeArgs = let
      default' = lib.concatStringsSep " " default;
      cross =
        lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${v}") fpcArchAttrs.makeArgs);
    in
      default' + " " + cross;
  in
    stdenv.mkDerivation (finalAttrs: rec {
      version = fpc.version;
      pname = "fpc";
      src = fpc.src;

      nativeBuildInputs = [findutils binutils gawk fpc];
      glibc = fpc.glibc;

      patches = fpc.patches;

      postPatch = ''
        # substitute the markers set by the mark-paths patch
        substituteInPlace compiler/systems/t_linux.pas --subst-var-by dynlinker-prefix "${glibc}"
        substituteInPlace compiler/systems/t_linux.pas --subst-var-by syslibpath "${glibc}/lib"
        # Replace the `codesign --remove-signature` command with a custom script, since `codesign` is not available
        # in nixpkgs
        # Remove the -no_uuid strip flag which does not work on llvm-strip, only
        # Apple strip.
        substituteInPlace compiler/Makefile \
          --replace \
            "\$(CODESIGN) --remove-signature" \
            "${fpc}/remove-signature.sh}" \
          --replace "ifneq (\$(CODESIGN),)" "ifeq (\$(OS_TARGET), darwin)" \
          --replace "-no_uuid" ""
      '';

      buildPhase = ''
        PATH="$PATH:${path}" \
          make all ${makeArgs}
      '';

      installPhase =
        ''
          make crossinstall ${makeArgs} ;
        ''
        + ''
          for i in $out/lib/fpc/${finalAttrs.version}/ppc*; do
            ln -fs $i $out/bin/$(basename $i)
          done
        '';

      meta = with lib; {
        description = "Free Pascal Compiler from a source distribution";
        homepage = "https://www.freepascal.org";
        maintainers = [maintainers.raskin];
        license = with licenses; [gpl2 lgpl2];
        platforms = platforms.unix;
        inherit archName fpc;
      };
    });
in rec {
  fpcCombo = {
    fpcCross,
    symlinkJoin,
    ...
  }: let
    fpcCrossAndBuild = symlinkJoin {
      name = "cross";
      paths = [fpcCross.meta.fpc fpcCross];
    };

    combo = {fpcJoined}:
      stdenv.mkDerivation (finalAttrs: {
        pname = "fpc-combo-${fpcCross.meta.archName}";
        version = fpcCross.version;

        phases = ["buildPhase"];

        buildPhase = ''
          mkdir -p $out
          ${pkgs.outils}/bin/lndir ${fpcJoined} $out
          cp $out/lib/fpc/etc/fpc.cfg $out/lib/fpc/etc/fpc.cfg.bak
          rm -f $out/lib/fpc/etc/fpc.cfg $out/etc/fpc.cfg
          substituteInPlace $out/lib/fpc/etc/fpc.cfg.bak \
            --replace "${fpcCross.meta.fpc}" "${fpcJoined}"
          mv $out/lib/fpc/etc/fpc.cfg.bak $out/lib/fpc/etc/fpc.cfg
          cp $out/lib/fpc/etc/fpc.cfg $out/etc/fpc.cfg
        '';
      });
  in
    pkgs.callPackage combo {fpcJoined = fpcCrossAndBuild;};

  fpcWrapper = {
    fpcAttrs,
    lib,
    writeShellScriptBin,
    fpcCross,
    callPackage,
  }: let
    c = callPackage fpcCombo {inherit fpcCross;};
  in
    writeShellScriptBin "fpc" ''
      PATH="$PATH:${lib.concatStringsSep ":" fpcAttrs.toolchainPaths}" PPC_CONFIG_PATH="${c}/etc" \
        ${c}/bin/pp${fpcAttrs.basename} \
          ${lib.concatStringsSep " " (fpcAttrs.wrapperArgs)} \
          ${lib.concatStringsSep " " (fpcAttrs.cpuArgs ++ [fpcAttrs.targetArg])} \
          $@
    '';
  lazarusWrapper = {
    lazarus,
    fpc,
    fpcAttrs,
    writeShellScriptBin,
    lib,
  }: let
    flags = lib.concatStringsSep " " [
      "--os=${fpcAttrs.makeArgs.OS_TARGET}"
      "--cpu=${fpcAttrs.makeArgs.CPU_TARGET}"
      "--lazarusdir=${lazarus}/share/lazarus"
      "--no-write-project"
    ];
    fpcBinaryPath = "${fpc}/bin";
    path = lib.concatStringsSep ":" (fpcAttrs.toolchainPaths ++ [fpcBinaryPath]);
  in
    writeShellScriptBin "lazbuild" ''
      HOME=$TMP INSTANTFPCCACHE=$TMP PATH="$PATH:${path}" \
        ${lazarus}/bin/lazbuild \
        ${flags} \
        $@
    '';

  lazarus = {
    stdenv,
    lib,
    fetchgit,
    writeText,
    fpc,
    ...
  }:
  # TODO:
  #  1. the build date is embedded in the binary through `$I %DATE%` - we should dump that
  let
    version = "3.0.0-0";

    # as of 2.0.10 a suffix is being added. That may or may not disappear and then
    # come back, so just leave this here.
    majorMinorPatch = v:
      builtins.concatStringsSep "." (lib.take 3 (lib.splitVersion v));

    overrides = writeText "revision.inc" (lib.concatStringsSep "\n"
      (lib.mapAttrsToList (k: v: "const ${k} = '${v}';") {
        # this is technically the SVN revision but as we don't have that replace
        # it with the version instead of showing "Unknown"
        RevisionStr = version;
      }));
  in
    stdenv.mkDerivation rec {
      pname = "lazarus-git-${pins.lazarus.src.rev}";
      inherit version;

      src = fetchgit {
        url = "https://gitlab.com/freepascal.org/lazarus/lazarus.git";
        rev = "lazarus_3_6";
        sha256 = "sha256-+ANj6rmK9QzgeEcnKOlejNi9FtCdtrHt24LcgszTNUE=";
      };

      postPatch = ''
        cp ${overrides} ide/${overrides.name}
      '';

      buildInputs = [
        fpc
      ];

      # Disable parallel build, errors:
      #  Fatal: (1018) Compilation aborted
      enableParallelBuilding = false;

      buildPhase = let
        makeFlags = [
          "FPC=fpc"
          "PP=fpc"
          "LAZARUS_INSTALL_DIR=$out/share/lazarus/"
          "INSTALL_PREFIX=$out/"
        ];
      in ''
        mkdir -p $out
        make lazbuild ${lib.concatStringsSep " " makeFlags}
      '';

      installPhase = let
        installFlags = [
          "FPC=fpc"
          "PP=fpc"
          "LAZARUS_INSTALL_DIR=${placeholder "out"}/share/lazarus/"
          "INSTALL_PREFIX=${placeholder "out"}/"
        ];
      in ''
        touch lazarus startlazarus
        make -k install ${lib.concatStringsSep " " installFlags}
      '';

      preBuild = ''
        mkdir -p $out/share/fpcsrc "$out/lazarus"
        cp -r ${fpc.src}/* $out/share/fpcsrc
        substituteInPlace ide/packages/ideconfig/include/unix/lazbaseconf.inc \
          --replace '/usr/fpcsrc' "$out/share/fpcsrc"
      '';

      meta = with lib; {
        description = "Graphical IDE for the FreePascal language";
        homepage = "https://www.lazarus.freepascal.org";
        license = licenses.gpl2Plus;
        maintainers = with maintainers; [raskin];
        platforms = platforms.linux;
      };
    };
  lazarus-3_6 = callPackage lazarus {};
  lazarus-trunk = lazarus-3_6.overrideAttrs (finalAttrs: {
    src = pins.lazarus.src;
  });

  fpcCross-trunk = callPackage fpcCrossDrv {fpc = fpc-trunk;};
  fpcCross-3_2_2 = callPackage fpcCrossDrv {fpc = fpc-3_2_2;};

  fpc-trunk = callPackage fpcDrv {};
  fpc = fpc-trunk;

  fpc-3_2_2 = fpc.overrideAttrs (final: prev: {
    version = "3.2.2";
    src = fetchgit {
      url = "https://gitlab.com/freepascal.org/fpc/source.git";
      rev = "0d122c49534b480be9284c21bd60b53d99904346";
      sha256 = "sha256-MBrcthXl6awecRe8CnMpPmLAsVhdMZHQD8GBukiuqeE=";
    };

    patches = [./mark-paths-3_2_2.patch];
  });

  fpc-3_0_4 = let
    oldPkgs =
      import (fetchgit {
        name = "fpc-3_0_4-revision";
        url = "https://github.com/NixOS/nixpkgs/";
        sha256 = "sha256-RRx+Tk/PKKoTDZh9HDi7cOEHx6sI5zx1Puxv67zS9Ng=";
        rev = "b5e903cedb331f9ee268ceebffb58069f1dae9fb";
      }) {
        inherit (pkgs) system;
      };
    drv = {archsAttrs ? {}, ...} @ args:
      (oldPkgs.fpc.override (lib.removeAttrs args ["archsAttrs"])).overrideAttrs (final: let
        default = ["NOGDB=1" "INSTALL_PREFIX=$out"];
      in {
        buildPhase =
          (
            if final ? buildPhase
            then final.buildPhase
            else ""
          )
          +
          # At the moment of writing this comment, author couldn't find a way to
          # compile a crosscompiling FPC without compiling an FPC native to the host system.
          # So what we do, is first we compile the "native" FPC compiler, and then the compilers for architectures passed through.
          (lib.concatStringsSep "\n" (
            lib.map (x: let
              arch = x.name;
              fpcAttrs = x.value;
            in ''
              PATH="$PATH:${lib.concatStringsSep ":" fpcAttrs.toolchainPaths}" \
                make crossall ${lib.concatStringsSep " " default} ${lib.concatStringsSep " " (lib.mapAttrsToList (name: value: "${name}=${value}") fpcAttrs.makeArgs)}
            '') (lib.attrsToList archsAttrs)
          ));

        installPhase =
          (
            if final ? installPhase
            then final.installPhase
            else ""
          )
          + lib.concatStringsSep "\n" (
            lib.map (x: let
              abi = x.name;
              fpcAttrs = x.value;
            in ''
              PATH="$PATH:${lib.concatStringsSep ":" fpcAttrs.toolchainPaths}" \
                make crossinstall ${lib.concatStringsSep " " default} ${lib.concatStringsSep " " (lib.mapAttrsToList (name: value: "${name}=${value}") fpcAttrs.makeArgs)}
            '') (lib.attrsToList archsAttrs)
          );
      });
  in
    callPackage drv {};
}
