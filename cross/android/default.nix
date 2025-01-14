{
  lib,
  pkgs,
  pins,
}: let
  customNdkPkgs = import ./ndk {
    inherit lib pkgs pins;
    inherit (pkgs) fetchFromGitHub stdenv;
  };

  buildToolsVersion = "35.0.0";
  cmakeVersion = "3.22.1";
  ndkVersion = "17.2.4988734";
  ndkBinutilsVersion = ndkVersion;
  platformToolsVersion = "35.0.2";
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [buildToolsVersion "28.0.3"];
    inherit platformToolsVersion;
    platformVersions = ["34" "31" "28" "21" "14"];
    abiVersions = ["armeabi-v7a" "arm64-v8a"];
    cmakeVersions = [cmakeVersion];
    includeNDK = true;
    ndkVersions = lib.unique [ndkVersion ndkBinutilsVersion];

    includeSources = false;
    includeSystemImages = false;
    useGoogleAPIs = false;
    useGoogleTVAddOns = false;
    includeEmulator = false;
  };
  androidSdk = androidComposition.androidsdk;
  androidNdk = "${androidSdk}/libexec/android-sdk/ndk-bundle";
  androidNdkBinutils = "${androidSdk}/libexec/android-sdk/ndk/${ndkBinutilsVersion}";
  androidPlatform = "14";

  architectures = {
    armv7 = rec {
      androidAbi = "armeabi-v7a";
      libArch = "arm";
      clangTriplet = "arm-linux-androideabi";
      compiler = "armv7a-linux-androideabi";
      sysroot = "${androidNdkBinutils}/toolchains/llvm/prebuilt/linux-x86_64/sysroot";
      ndkLib = "${sysroot}/usr/lib/${clangTriplet}/${androidPlatform}";
      ndkLibOld = "${androidNdkBinutils}/platforms/android-${androidPlatform}/arch-${libArch}/usr/lib";
      ndkToolchain = "${androidNdk}/toolchains/llvm/prebuilt/linux-x86_64/bin";
      ndkToolchainOld = "${androidNdk}/toolchains/${clangTriplet}-4.9/prebuilt/linux-x86_64/bin";
      ndkBinutilsToolchain = ndkToolchainOld;
      name = "android-armeabi-v7a";
      isAndroid = true;
      isWindows = false;
      bundleFormats = ["apk"];
      caseSensitive = true;
      pretty = "Android ${androidAbi}, platform level ${androidPlatform}, NDK ${ndkVersion}";
      d2dforeverFeaturesSuport = {
        openglDesktop = false;
        openglEs = true;
        supportsHeadless = false;
        loadedAsLibrary = true;
      };
      fpcAttrs = rec {
        lazarusExists = false;
        cpuArgs = ["-CpARMV7A" "-CfVFPV3" "-Fl${ndkLib}" "-Fl${ndkLibOld}" "-XP${ndkToolchainOld}/${clangTriplet}-"];
        targetArg = "-Tandroid";
        basename = "crossarm";
        makeArgs = {
          OS_TARGET = "android";
          CPU_TARGET = "arm";
          CROSSOPT = "\"" + (lib.concatStringsSep " " cpuArgs) + "\"";
          NDK = "${androidNdk}";
        };
        toolchainPaths = [
          ndkToolchain
          ndkToolchainOld
          ndkBinutilsToolchain
        ];
      };
    };

    armv8 = rec {
      androidAbi = "arm64-v8a";
      libArch = "arm64";
      clangTriplet = "aarch64-linux-android";
      compiler = clangTriplet;
      sysroot = "${androidNdkBinutils}/toolchains/llvm/prebuilt/linux-x86_64/sysroot";
      ndkLib = "${sysroot}/usr/lib/${clangTriplet}/${androidPlatform}";
      # FIXME
      # Hardcoded Android 21 platform, where armv8 support was added.
      ndkLibOld = "${androidNdkBinutils}/platforms/android-21/arch-${libArch}/usr/lib";
      ndkToolchain = "${androidNdk}/toolchains/llvm/prebuilt/linux-x86_64/bin";
      ndkToolchainOld = "${androidNdk}/toolchains/${clangTriplet}-4.9/prebuilt/linux-x86_64/bin";
      ndkBinutilsToolchain = ndkToolchainOld;
      name = "android-arm64-v8a";
      isAndroid = true;
      isWindows = false;
      bundleFormats = ["apk"];
      caseSensitive = true;
      pretty = "Android ${androidAbi}, platform level ${androidPlatform}, NDK ${ndkVersion}";
      d2dforeverFeaturesSuport = {
        openglDesktop = false;
        openglEs = true;
        supportsHeadless = false;
        loadedAsLibrary = true;
      };
      fpcAttrs = rec {
        lazarusExists = false;
        cpuArgs = ["-CpARMV8" "-CfVFP" "-Fl${ndkLib}" "-Fl${ndkLibOld}" "-XP${ndkToolchainOld}/${clangTriplet}-"];
        targetArg = "-Tandroid";
        basename = "crossa64";
        makeArgs = {
          OS_TARGET = "android";
          CPU_TARGET = "aarch64";
          CROSSOPT = "\"" + (lib.concatStringsSep " " cpuArgs) + "\"";
          NDK = "${androidNdk}";
        };
        toolchainPaths = [
          ndkToolchain
          ndkToolchainOld
          ndkBinutilsToolchain
        ];
      };
    };
  };

  ndkPackagesByArch =
    lib.mapAttrs' (abi: abiAttrs: let
      inherit (abiAttrs) androidAbi;
      enet = customNdkPkgs.enet {
        inherit androidSdk androidNdk androidAbi androidPlatform;
      };
      SDL2 = customNdkPkgs.SDL2 {
        inherit androidSdk androidNdk androidAbi androidPlatform;
      };
      libogg = customNdkPkgs.libogg {
        inherit androidSdk androidNdk androidAbi androidPlatform;
      };
      libopus = customNdkPkgs.libopus {
        inherit androidSdk androidNdk androidAbi androidPlatform;
      };
      libxmp = customNdkPkgs.libxmp {
        inherit androidSdk androidNdk androidAbi androidPlatform;
      };
      openal =
        (customNdkPkgs.openal {
          inherit androidSdk androidNdk androidAbi androidPlatform;
          cmakeExtraArgs = lib.concatStringsSep " " [
            "-DALSOFT_UTILS=off"
            "-DALSOFT_EXAMPLES=off"
            "-DALSOFT_BACKEND_SDL2=on"
            "-DALSOFT_REQUIRE_SDL2=on"
            "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH"
            "-DCMAKE_PREFIX_PATH=${SDL2}"
            "-DCMAKE_FIND_ROOT_PATH=${SDL2}"
          ];
        })
        .overrideAttrs (prev: {
          preBuild = ''
            rm -r build
          '';
        });
      libvorbis = customNdkPkgs.libvorbis {
        inherit androidSdk androidNdk androidAbi androidPlatform;
        cmakeExtraArgs = lib.concatStringsSep " " [
          "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH"
          "-DCMAKE_PREFIX_PATH=${libogg}"
          "-DCMAKE_FIND_ROOT_PATH=${libogg}"
        ];
      };
      game-music-emu = customNdkPkgs.game-music-emu {
        inherit androidSdk androidNdk androidAbi androidPlatform;
        cmakeExtraArgs = "-DENABLE_UBSAN=off";
      };
      libmpg123 = customNdkPkgs.libmpg123 {
        inherit androidSdk androidNdk androidAbi androidPlatform;
        cmakeListsPath = "ports/cmake";
      };
      libmodplug = customNdkPkgs.libmodplug {
        inherit androidSdk androidNdk androidAbi androidPlatform;
      };
      fluidsynth =
        (customNdkPkgs.fluidsynth {
          inherit androidSdk androidNdk androidAbi androidPlatform;
          cmakeExtraArgs = lib.concatStringsSep " " [
            "-DBUILD_SHARED_LIBS=on"
            "-Denable-threads=off"
            "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH"
            "-Denable-sdl2=on"
            "-Denable-oboe=on"
            "-Denable-opensles=on"
            "-DCMAKE_PREFIX_PATH=${SDL2}"
            "-DANDROID_NDK=${androidNdk}"
            "-DANDROID_COMPILER_FLAGS=\"-shared\""
          ];
        })
        .overrideAttrs (final: prev: {
          nativeBuildInputs = [pkgs.buildPackages.stdenv.cc pkgs.pkg-config];
          installPhase =
            prev.installPhase
            + ''
              [[ -e "$out/lib64/libfluidsynth.so" ]] && cp -r $out/lib64/* $out/lib/ || :
            '';
        });
      wavpack = customNdkPkgs.wavpack {
        inherit androidSdk androidNdk androidAbi androidPlatform;
        # fails on armv7 32 bit
        # See https://github.com/curl/curl/pull/13264
        cmakeExtraArgs = "-DCMAKE_REQUIRED_FLAGS=\"-D_FILE_OFFSET_BITS=64\"";
      };

      opusfile =
        (customNdkPkgs.opusfile {
          inherit androidSdk androidNdk androidAbi androidPlatform;
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
        (customNdkPkgs.SDL2_mixer {
          inherit androidSdk androidNdk androidAbi androidPlatform;

          cmakeExtraArgs = let
            libs = pkgs.symlinkJoin {
              name = "cmake-packages";
              paths =
                [libxmp fluidsynth wavpack SDL2 libopus libogg game-music-emu libmodplug libmpg123]
                # These are projects which are broken regarding packaging.
                # Specify their path manually.
                ++ [
                  # vorbis
                  # opusfile
                ];
            };
          in
            lib.concatStringsSep " " [
              "-DBUILD_SHARED_LIBS=on"
              "-DSDL2MIXER_VENDORED=off"

              "-DSDL2MIXER_VORBIS=VORBISFILE"
              "-DSDL2MIXER_VORBIS_VORBISFILE_SHARED=off"
              "-DVorbis_vorbisfile_INCLUDE_PATH=${libvorbis}/include"
              "-DVorbis_vorbisfile_LIBRARY=${libvorbis}/lib/libvorbisfile.so"

              "-DSDL2MIXER_MP3=on"
              "-DSDL2MIXER_MP3_MPG123=on"
              "-DSDL2MIXER_MP3_MPG123_SHARED=off"

              "-DSDL2MIXER_OPUS=on"
              "-DSDL2MIXER_OPUS_SHARED=off"
              "-DOpusFile_LIBRARY=${opusfile}/lib/libopusfile.so"
              "-DOpusFile_INCLUDE_PATH=${opusfile}/include"

              "-DSDL2MIXER_GME=on"
              "-DSDL2MIXER_GME_SHARED=off"

              "-DSDL2MIXER_MIDI=on"
              "-DSDL2MIXER_MIDI_TIMIDITY=on"
              "-DSDL2MIXER_MIDI_FLUIDSYNTH=on"
              "-DSDL2MIXER_MIDI_FLUIDSYNTH_SHARED=off"

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
    in {
      name = abiAttrs.name;
      value = {
        infoAttrs = abiAttrs;
        inherit androidSdk;
        inherit enet SDL2 SDL2_mixer opusfile libogg libopus libxmp fluidsynth wavpack libvorbis game-music-emu libmodplug openal libmpg123;
      };
    })
    architectures;
in
  ndkPackagesByArch
