{
  pkgs,
  lib,
  pins,
  osxcross,
}: let
  toolchain = osxcross.packages.${pkgs.system}.toolchain_15_2;
  sdk = "${toolchain}/SDK/MacOSX15.2.sdk";
  target = "apple-darwin22.1";
  mkMacArch = target: fpcCpu: fpcBinary: {
    caseSensitive = true;
    d2dforeverFeaturesSuport = {
      openglDesktop = true;
      openglEs = true;
      supportsHeadless = true;
      loadedAsLibrary = false;
    };
    isWindows = false;
    majorPlatform = "macOS";
    appBundleName = fpcCpu;
    bundleFormats = ["zip" "apple"];
    bundle = {
      io = "SDL2";
      sound = "OpenAL";
      graphics = "OpenGL2";
      headless = "Disable";
      holmes = "Enable";
      assets.midiBank = "soundfont";
    };
    fpcAttrs = rec {
      cpuArgs = [
        "-XP${toolchain}/bin/${target}-"
        "-Fl${sdk}/usr/lib"
        "-Fl${sdk}/usr/lib/system"
        "-k-F${sdk}/System/Library/Frameworks/"
        "-k-L${sdk}/usr/lib"
        "-k-L${sdk}/usr/lib/system"
        #"-k-mmacosx-version-min=11.0"
      ];
      # Tests revealed that there are some problems with FPC's aarch64 cpu target.
      # To try to workaround that, use as few optimizations as possible.
      # On an Apple silicon Mac:
      # 1. Titlepic is sometimes used instead of some textures on the map, covering half of the map.
      # 2. Bus errors, unaligned access.
      wrapperArgs = [
        "-O1"
        "-g"
        "-gl"
        "-k-headerpad_max_install_names"
      ];
      targetArg = "-Tdarwin";
      basename = fpcBinary;
      makeArgs = {
        OS_TARGET = "darwin";
        CPU_TARGET = fpcCpu;
        CROSSOPT = "\"" + (lib.concatStringsSep " " cpuArgs) + "\"";
      };
      lazarusExists = false;
      toolchainPaths = [
        "${toolchain}/bin"
      ];
    };
  };
  mkMacCrossPkg = target: triplet: fpcCpu: fpcBinary: let
    common = import ../_common {
      inherit lib pkgs pins;
      arch = triplet;
      cmake = let
        macosDeploymentTarget =
          if fpcCpu == "aarch64"
          then "11.0"
          else "11.0";
        CFLAGS = lib.concatStringsSep " " [
          "-target ${target}"
          "-resource-dir ${pkgs.llvmPackages_17.clang-unwrapped.lib}/lib/clang/17"
          "-isysroot ${sdk}"
          "-isystem ${sdk}/usr/include"
          "-iframework ${sdk}/System/Library/Frameworks"
          "-I${pkgs.llvmPackages_17.clang-unwrapped.lib}/lib/clang/17/include"
          "-I${sdk}/usr/include"
        ];
        CXXFLAGS = CFLAGS;
        LDFLAGS = lib.concatStringsSep " " [
          "-target ${target}"
          "-I${pkgs.llvmPackages_17.clang-unwrapped.lib}/lib/clang/17/include"
          "-L${sdk}/usr/lib"
          "-L${sdk}/usr/lib/system"
          "-I${sdk}/usr/include"
          "-headerpad_max_install_names"
          # https://github.com/libsdl-org/SDL/issues/6491
          #"-lclang_rt.osx"
        ];
        exports = [
          "OSXCROSS_SDK='${sdk}'"
          "OSXCROSS_HOST='${target}'"
          "OSXCROSS_TARGET='${toolchain}'"
          "OSXCROSS_TARGET_DIR='${toolchain}'"
          "OSXCROSS_CLANG_INTRINSIC_PATH='${pkgs.llvmPackages_17.clang-unwrapped.lib}/lib/clang/'"
          "CFLAGS=\"$CFLAGS ${CFLAGS}\""
          "CXXFLAGS=\"$CXXFLAGS ${CXXFLAGS}\""
          "LDFLAGS=\"$LDFLAGS ${LDFLAGS}\""
        ];
        cmakeFlags = lib.concatStringsSep " " [
          "-DCMAKE_TOOLCHAIN_FILE=${osxcross}/tools/toolchain.cmake"
          "-DCMAKE_OSX_DEPLOYMENT_TARGET=\"${macosDeploymentTarget}\""
          "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
        ];
      in "${lib.concatStringsSep " " exports} ${pkgs.cmake}/bin/cmake ${cmakeFlags}";
    };
  in
    lib.recursiveUpdate common {
      infoAttrs = mkMacArch target fpcCpu fpcBinary;
      macdylibbundler = pkgs.macdylibbundler;
      rcodesign = pkgs.rcodesign;
      cctools = pkgs.cctools;
    };
in {
  arm64-apple-darwin = mkMacCrossPkg "aarch64-apple-darwin22.1" "aarch64-apple-darwin" "aarch64" "crossa64";
  x86_64-apple-darwin = mkMacCrossPkg "x86_64-apple-darwin22.1" "x86_64-apple-macosx11.0.0" "x86_64" "cx64";
}
