{
  pkgs,
  lib,
  pins,
}: let
  mkArch = arch: let
    osSuffix = "gnu";
    pkgsCross = pkgs.pkgsCross."gnu${arch}";
    processor =
      if arch == "32"
      then "x86"
      else "x86_64";
    prefix = "${processor}-unknown-linux-${osSuffix}";
    stdenvCC = pkgsCross.gcc;
    toolchainPrefix = "${stdenvCC}/bin/";
    cc = "${toolchainPrefix}cc";
    cxx = "${toolchainPrefix}c++";
    ar = "${toolchainPrefix}ar";
    ld = "${toolchainPrefix}ld";
    ranlib = "${toolchainPrefix}ranlib";
    isStatic = false;
    shared =
      if isStatic
      then "off"
      else "on";
    static =
      if isStatic
      then "on"
      else "off";
    cmakeToolchainFile = pkgs.writeTextFile {
      name = "gnu${arch}.cmake-toolchain";
      text = ''
        #set(MUSL TRUE)
        set(CMAKE_SYSTEM_PROCESSOR ${processor})
        set(CMAKE_HOST_SYSTEM_PROCESSOR x86_64)
        set(CMAKE_HOST_SYSTEM_NAME Linux)
        set(CMAKE_SYSTEM_NAME Linux)
        set(CMAKE_CROSSCOMPILING TRUE)
        set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
        cmake_policy(SET CMP0077 NEW)
        # never search for programs in the build host directories
        # otherwise, some programs may pick up glibc for example
        set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
        set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
        set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
        set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
        set(CMAKE_FIND_ROOT_PATH
          "${cc}")
        set(CMAKE_C_COMPILER "${cc}")
        set(CMAKE_CXX_COMPILER "${cxx}")
        set(CMAKE_AR "${ar}")
        set(CMAKE_C_COMPILER_AR "${ar}")
        set(CMAKE_CXX_COMPILER_AR "${ar}")
        set(CMAKE_RANLIB "${ranlib}")
        set(CMAKE_C_COMPILER_RANLIB "${ranlib}")
        set(CMAKE_CXX_COMPILER_RANLIB "${ranlib}")
        set(CMAKE_LD "${ld}")
        set(CMAKE_FIND_LIBRARY_SUFFIXES ".so")
        set(BUILD_SHARED_LIBS ${shared})
      '';
    };
    CFLAGS = lib.concatStringsSep " " ["-fPIC" "-static-libgcc"];
    CXXFLAGS = CFLAGS + " -static-libstdc++ ";
    # libxmp requires -lm to be present, otherwise fails with `undefined reference to sin` and other similar symbols
    LDFLAGS = " -static-libgcc -static-libstdc++ -lm ";
    env = {
      PATH = "$PATH:${stdenvCC}/bin";
      CFLAGS = "$CFLAGS ${CFLAGS}";
      CXXFLAGS = "$CXXFLAGS ${CXXFLAGS}";
      LDFLAGS = "$LDFLAGS ${LDFLAGS}";
      LD = "${ld}";
      AR = "${ar}";
      RANLIB = "${ranlib}";
    };
    cmakeFlags = lib.concatStringsSep " " [
      "-DCMAKE_TOOLCHAIN_FILE=${cmakeToolchainFile}"
    ];
    cmake = let
      envStringArray = lib.map (var: "${var.name}=\"${var.value}\"") (lib.attrsToList env);
      envInlined = lib.concatStringsSep " " envStringArray;
    in
      "${envInlined} ${lib.getExe pkgsCross.buildPackages.cmake} ${cmakeFlags}";
    stdenv = pkgsCross.stdenvNoCC;

    newCrossPkgs = import ../_common {
      inherit lib pkgs pins;
      arch = "linux-gnu${arch}";
      inherit cmake stdenv;
    };
  in
    lib.recursiveUpdate newCrossPkgs {
      SDL2 = pkgsCross.SDL2;
      openal = pkgsCross.openal;
      SDL2_mixer = pkgsCross.SDL2_mixer;
      infoAttrs = {
        caseSensitive = true;
        d2dforeverFeaturesSuport = {
          openglDesktop = true;
          openglEs = true;
          supportsHeadless = true;
          loadedAsLibrary = false;
        };
        isWindows = false;
        majorPlatform = "linux";
        bundleFormats = ["zip" "appimage"];
        bundle = {
          io = "SDL2";
          sound = "OpenAL";
          graphics = "OpenGL2";
          headless = "Disable";
          holmes = "Enable";
          assets.midiBank = "soundfont";
        };
        fpcAttrs = rec {
          lazarusExists = false;
          cpuArgs = ["-Cg" "-fPIC"];
          wrapperArgs = ["-O1" "-g" "-gl" "-Cg" "-k-pie" "-k-pic"];
          targetArg = "-Tlinux";
          basename = "cx64";
          makeArgs = {
            OS_TARGET = "linux";
            CPU_TARGET = "x86_64";
            CROSSOPT = "\"" + (lib.concatStringsSep " " cpuArgs) + "\"";
          };
          toolchainPaths = [
          ];
        };
      };
    };
in {
  linux-gnu64 = mkArch "64";
}
