{
  lib,
  pkgs,
  fetchFromGitHub,
  stdenv,
  pins,
}: let
  androidCmakeDrv = {
    pname,
    version,
    src,
  }: {
    androidSdk,
    androidNdk,
    androidAbi,
    androidPlatform,
    cmakeListsPath ? null,
    cmakePrefix ? "",
    cmakeExtraArgs ? "",
    ...
  }: let
    cmake = "${pkgs.cmake}/bin/cmake";

    # NDK r17 has a bug with ncurses5.
    # https://github.com/android/ndk/issues/574
    # This is a workaround.
    ncursesFixed = pkgs.stdenvNoCC.mkDerivation {
      pname = "libtinfo-symlink";
      version = "${pkgs.ncurses5.version}";

      src = null;
      dontUnpack = true;

      installPhase = ''
        mkdir -p $out/lib
        ln -s "${pkgs.ncurses5}/lib/libtinfo.so" "$out/lib/libtinfo.so.5"
      '';
    };
  in
    pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      inherit version src;
      pname = "${pname}-${androidAbi}";

      dontStrip = true;
      dontPatchELF = true;

      phases = ["unpackPhase" "buildPhase" "installPhase"];

      nativeBuildInputs = [pkgs.cmake pkgs.gnumake];

      # -DCMAKE_POLICY_DEFAULT_CMP0057=NEW \
      buildPhase = ''
        runHook preBuild
        ${lib.optionalString (!builtins.isNull cmakeListsPath) "cd ${cmakeListsPath}"}
        mkdir build
        cd build
        # Provide libtinfo for bugged NDK clang versions
        export LD_LIBRARY_PATH="${ncursesFixed}/lib"
        ${cmakePrefix} \
          ${cmake} .. \
            -DCMAKE_MAKE_PROGRAM=${pkgs.gnumake}/bin/make \
            -DCMAKE_TOOLCHAIN_FILE="${androidNdk}/build/cmake/android.toolchain.cmake" \
            -DBUILD_SHARED_LIBS=ON -DANDROID_ABI=${androidAbi} -DANDROID_PLATFORM=android-${androidPlatform} \
            -DCMAKE_BUILD_TYPE=Release \
            -DANDROID_NDK=${androidNdk} \
            -DCMAKE_INSTALL_PREFIX=$out -DANDROID_STL=c++_static \
            ${cmakeExtraArgs}
        make -j$(nproc)
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib
        make install
        runHook postInstall
      '';
    });
in rec {
  SDL2 = androidCmakeDrv rec {
    pname = "SDL2";
    version = pins.SDL2.version;
    src = pins.SDL2.src;
  };

  enet = androidCmakeDrv {
    pname = "enet";
    version = pins.enet.version;
    src = pins.enet.src;
  };

  SDL2_mixer = androidCmakeDrv {
    pname = "SDL2_mixer";
    version = pins.SDL2_mixer.version;
    src = pins.SDL2_mixer.src;
  };

  # Upstream packaging is horrendous.
  opusfile = androidCmakeDrv {
    pname = "opusfile";
    version = pins.opusfile.version;
    src = pins.opusfile.src;
  };

  libogg = androidCmakeDrv {
    pname = "libogg";
    version = pins.libogg.version;
    src = pins.libogg.src;
  };

  libopus = androidCmakeDrv {
    pname = "opus";
    version = pins.libopus.version;
    src = pins.libopus.src;
  };

  libxmp = androidCmakeDrv {
    pname = "libxmp";
    version = pins.libxmp.version;
    src = pins.libxmp.src;
  };

  fluidsynth = androidCmakeDrv {
    pname = "fluidsynth";
    version = pins.fluidsynth.version;
    src = pins.fluidsynth.src;
  };

  wavpack = androidCmakeDrv {
    pname = "wavpack";
    version = pins.wavpack.version;
    src = pins.wavpack.src;
  };

  libmpg123 = androidCmakeDrv {
    pname = "mpg123";
    version = pins.libmpg123.version;
    src = pins.libmpg123.src;
  };

  libvorbis = androidCmakeDrv {
    pname = "vorbis";
    version = pins.libvorbis.version;
    src = pins.libvorbis.src;
  };

  game-music-emu = androidCmakeDrv {
    pname = "game-music-emu";
    version = pins.game-music-emu.version;
    src = pins.game-music-emu.src;
  };

  libmodplug = androidCmakeDrv {
    pname = "libmodplug";
    version = pins.libmodplug.version;
    src = pins.libmodplug.src;
  };

  openal = androidCmakeDrv {
    pname = "openal-soft";
    version = pins.openal.version;
    src = pins.openal.src;
  };
}
