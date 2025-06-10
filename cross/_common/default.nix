{
  pins,
  pkgs,
  lib,
  cmake,
  arch,
}: let
  _cmakeDrv = {
    cmake,
    arch,
  }: {
    pname,
    version,
    src,
    licenseFiles ? [],
  }: {
    cmakeListsPath ? null,
    cmakePrefix ? "",
    cmakeExtraArgs ? "",
    extraCmds ? "",
  }:
    pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      inherit src;
      pname = "${pname}";
      version = "${version}-${arch}";

      dontStrip = true;
      dontPatchELF = true;

      phases = ["unpackPhase" "buildPhase" "installPhase"];

      buildPhase = ''
        runHook preBuild
        ${lib.optionalString (!builtins.isNull cmakeListsPath) "cd ${cmakeListsPath}"}
        ${extraCmds}
        mkdir build
        cd build
        ${cmakePrefix} \
          ${cmake} \
            -DBUILD_SHARED_LIBS=ON \
            -DCMAKE_INSTALL_PREFIX=$out \
            -DCMAKE_CROSSCOMPILING=ON \
            ${cmakeExtraArgs} \
            ..
        make -j$(nproc)
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib
        make install
        runHook postInstall
      '';

      meta = lib.optionalAttrs (licenseFiles != []) {
        inherit licenseFiles;
      };
    });
  buildCmakeProject = _cmakeDrv {inherit cmake arch;};
  source = (import ./_source.nix {inherit pins;}) {
    cmakeDrv = buildCmakeProject;
  };
  findLib = path: name: "$(${pkgs.findutils}/bin/find ${path}/lib -maxdepth 1 -type f -iname '*${name}*' | head -n1)";
in rec {
  enet = (source.enet {
    })
    .overrideAttrs (final: prev: {
    installPhase =
      prev.installPhase
        or ""
      + ''
        mv $out/bin/libenet.dll $out/bin/enet.dll || :
      '';
  });
  SDL2 = source.SDL2 {
    cmakeExtraArgs = "-DSDL_WERROR=OFF";
    extraCmds = ''
      substituteInPlace src/sensor/android/SDL_androidsensor.c \
          --replace 'ALooper_pollAll' 'ALooper_pollOnce' || :
    '';
  };
  libogg =
    source.libogg {
    };
  libopus =
    source.libopus {
    };
  libxmp =
    source.libxmp {
    };
  openal =
    (source.openal {
      cmakeExtraArgs = lib.concatStringsSep " " [
        "-DALSOFT_UTILS=off"
        "-DALSOFT_EXAMPLES=off"
        "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH"
      ];
    })
    .overrideAttrs (prev: {
      preBuild = ''
        rm -r build
      '';
    });
  libvorbis =
    (source.libvorbis {
      cmakeExtraArgs = lib.concatStringsSep " " [
        "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH"
        "-DCMAKE_PREFIX_PATH=${libogg}"
        "-DCMAKE_FIND_ROOT_PATH=${libogg}"
        "-DOGG_LIBRARY=${findLib libogg "libogg"}"
        "-DOGG_INCLUDE_DIR=${libogg}/include/"
      ];
    })
    .overrideAttrs (finalAttrs: {
      buildInputs = finalAttrs.buildInputs or [] ++ [pkgs.gnused];
      preBuild =
        finalAttrs.preBuild
        or ""
        + ''
          sed -E -i 's/vorbis.def|vorbisenc.def|vorbisfile.def//g' lib/CMakeLists.txt
        '';
    });
  game-music-emu = source.game-music-emu {
    cmakeExtraArgs = "-DENABLE_UBSAN=off";
  };
  libmpg123 = source.libmpg123 {
    cmakeListsPath = "ports/cmake";
    cmakeExtraArgs = "-DBUILD_LIBOUT123=off";
  };
  libmodplug =
    source.libmodplug {
    };
  miniupnpc = (source.miniupnpc {
    })
    .overrideAttrs (final: prev: {
    installPhase =
      prev.installPhase
        or ""
      + ''
        mv $out/bin/libminiupnpc.dll $out/bin/miniupnpc.dll || :
      '';
  });
  fluidsynth =
    (source.fluidsynth {
      cmakeExtraArgs = lib.concatStringsSep " " [
        "-Denable-framework=off"
      ];
    })
    .overrideAttrs (final: prev: {
      nativeBuildInputs = [pkgs.buildPackages.stdenv.cc pkgs.pkg-config pkgs.findutils];
      installPhase =
        prev.installPhase
        + ''
          [[ -d "$out/lib64" ]] && find $out/lib64/ -exec cp {} $out/lib \; || echo :
          mv $out/bin/libfluidsynth-3.dll $out/bin/libfluidsynth.dll || :
        '';
    });
  wavpack = source.wavpack {
    # fails on armv7 32 bit
    # See https://github.com/curl/curl/pull/13264
    cmakeExtraArgs = "-DCMAKE_REQUIRED_FLAGS=\"-D_FILE_OFFSET_BITS=64\"";
  };

  opusfile =
    (source.opusfile {
      cmakeExtraArgs = lib.concatStringsSep " " [
        "-DOP_DISABLE_HTTP=on"
        "-DOP_DISABLE_DOCS=on"
        "-DOP_DISABLE_HTTP=on"
        "-DOP_DISABLE_EXAMPLES=on"
        "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH"
        "-DCMAKE_PREFIX_PATH=${pkgs.symlinkJoin {
          name = "cmake-packages";
          paths = [libogg libopus];
        }}"
      ];
    })
    .overrideAttrs (prev: {
      buildPhase =
        ''
          substituteInPlace CMakeLists.txt \
          --replace "list(GET PROJECT_VERSION_LIST 1 PROJECT_VERSION_MINOR)" ""
        ''
        + prev.buildPhase;
      installPhase =
        prev.installPhase
        + ''
          substituteInPlace $out/include/opus/opusfile.h \
          --replace "<opus_multistream.h>" "<opus/opus_multistream.h>"
        '';
      nativeBuildInputs = [pkgs.pkg-config];
    });

  SDL2_mixer =
    (source.SDL2_mixer {
      cmakeExtraArgs = let
        libs = pkgs.symlinkJoin {
          name = "cmake-packages";
          paths =
            [libxmp wavpack SDL2 libopus libogg libmodplug libmpg123]
            # These are projects which sometimes can't be found on some platforms.
            # Specify their path manually.
            ++ [
              # vorbis
              # opusfile
              # game-music-emu
              # fluidsynth
            ];
        };
      in
        lib.concatStringsSep " " [
          "-DBUILD_SHARED_LIBS=on"
          "-DSDL2MIXER_VENDORED=off"

          "-DSDL2MIXER_VORBIS=VORBISFILE"
          "-DSDL2MIXER_VORBIS_VORBISFILE_SHARED=off"
          "-DVorbis_vorbisfile_INCLUDE_PATH=${libvorbis}/include"
          "-DVorbis_vorbisfile_LIBRARY=${findLib libvorbis "libvorbisfile"}"

          "-DSDL2MIXER_MP3=on"
          "-DSDL2MIXER_MP3_MPG123=on"
          "-DSDL2MIXER_MP3_MPG123_SHARED=off"

          "-DSDL2MIXER_OPUS=on"
          "-DSDL2MIXER_OPUS_SHARED=off"
          "-DOpusFile_LIBRARY=${findLib opusfile "libopusfile"}"
          "-DOpusFile_INCLUDE_PATH=${opusfile}/include"

          "-DSDL2MIXER_GME=on"
          "-DSDL2MIXER_GME_SHARED=off"
          "-Dgme_LIBRARY=${findLib game-music-emu "libgme"}"
          "-Dgme_INCLUDE_PATH=${game-music-emu}/include"

          "-DSDL2MIXER_MIDI=on"
          "-DSDL2MIXER_MIDI_TIMIDITY=on"
          "-DSDL2MIXER_MIDI_FLUIDSYNTH=off"
          #"-DSDL2MIXER_MIDI_FLUIDSYNTH_SHARED=off"
          #"-DFluidSynth_LIBRARY=${findLib fluidsynth "libfluidsynth"}"
          #"-DFluidSynth_INCLUDE_PATH=${fluidsynth}/include"

          "-DSDL2MIXER_MOD=on"
          "-DSDL2MIXER_MOD_MODPLUG=off"
          "-DSDL2MIXER_MOD_XMP=on"
          "-DSDL2MIXER_MOD_XMP_SHARED=off"

          "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH"
          "-DCMAKE_PREFIX_PATH=${libs}"
          "-DCMAKE_FIND_ROOT_PATH=${libs}"
          "-DSDL2MIXER_MOD_XMP_SHARED=off"
        ];
    })
    .overrideAttrs (prev: {
      nativeBuildInputs = [pkgs.pkg-config];
    });
}
