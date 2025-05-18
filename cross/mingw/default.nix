{
  pkgs,
  lib,
  pins,
}: let
  mkMingwCrossPkg = arch': vendor: sys: nixpkgsArch: fpcTarget: fpcCpu: fpcBasename: chosenMatrix: let
    crossPkgs = pkgs.pkgsCross.${nixpkgsArch};
    gcc =
      crossPkgs.buildPackages.wrapCC
      (
        crossPkgs.buildPackages.gcc-unwrapped.override (prev: {
          threadsCross = {
            model = "win32";
            package = null;
          };
        })
      );

    # Win XP+, presumably
    stdenvWin32Threads = crossPkgs.buildPackages.overrideCC crossPkgs.stdenv gcc;

    # Windows 7+, presumably
    stdenvDefault = crossPkgs.stdenv;

    matrix = {
      win32Threads = {
        stdenv = stdenvWin32Threads;
        winNt = "0x0400";
        CFLAGS = [];
        LDFLAGS = [];
      };
      mcfgthread = {
        stdenv = stdenvDefault;
        winNt = "0x0601";
        CFLAGS = [
          "-pthread"
          "-I${crossPkgs.windows.mcfgthreads.dev}/include"
          "-I${crossPkgs.windows.mingw_w64_pthreads}/include"
        ];
        LDFLAGS = [
          "-pthread"
          "-L${crossPkgs.windows.mcfgthreads}/lib"
          "-L${crossPkgs.windows.mingw_w64_pthreads}/lib"
        ];
      };
    };
    activeMatrix = matrix."${chosenMatrix}";
    stdenv = activeMatrix.stdenv;
    fmodex = let
      drv = {
        stdenv,
        lib,
        fetchurl,
        p7zip,
        is64Bit ? arch' == "x86_64",
        installerHasSuffix ? true,
      }: let
        installerSuffix = lib.optionalString installerHasSuffix (
          if is64Bit
          then "64"
          else "32"
        );
        version = "4.28.07";
        shortVersion = builtins.replaceStrings ["."] [""] version;
        src = fetchurl {
          url = "https://zdoom.org/files/fmod/fmodapi${shortVersion}win${installerSuffix}-installer.exe";
          sha256 =
            if is64Bit
            then "sha256-F6kFWvkpbUawIMSZBLoHytlth/T3QUSS+Ke7cU1O12c="
            else "sha256-aPK+/b1dwo1MsegzXTaxBozF56Rko0jxBJYuVi1f0LQ=";
        };
      in let
        license = stdenv.mkDerivation {
          pname = "fmodex-license";
          version = "${installerSuffix}-${version}";
          inherit shortVersion;
          nativeBuildInputs = [p7zip];
          unpackPhase = false;
          dontUnpack = true;
          dontStrip = true;
          dontPatchELF = true;
          dontBuild = true;

          installPhase = ''
            mkdir -p $out
            7z e -aoa ${src}
            cp LICENSE.TXT $out/
          '';
        };
      in
        stdenv.mkDerivation {
          pname = "fmodex";
          version = "${installerSuffix}-${version}";
          inherit shortVersion;
          nativeBuildInputs = [p7zip];
          unpackPhase = false;
          dontUnpack = true;
          dontStrip = true;
          dontPatchELF = true;
          dontBuild = true;

          installPhase = let
            dllSuffix = lib.optionalString installerHasSuffix (lib.optionalString is64Bit "64");
          in ''
            mkdir -p $out/bin
            7z e -aoa ${src}
            cp fmodex${dllSuffix}.dll $out/bin/fmodex.dll
          '';

          meta = with lib; {
            licenseFiles = ["${license}/LICENSE.TXT"];
            description = "Programming library and toolkit for the creation and playback of interactive audio";
            homepage = "http://www.fmod.org/";
            license = licenses.unfreeRedistributable;
            platforms = [
              "i686-mingw32"
            ];
            maintainers = [];
          };
        };
    in
      pkgs.callPackage drv {};
    set = import ../_common rec {
      inherit lib pkgs pins;
      arch = "${arch'}-${vendor}-${sys}";
      cmake = let
        inherit stdenv;
        inherit ld as;
        winNt = activeMatrix.winNt;
        cc = stdenv.cc;
        windres = "${pkgs.writeShellScript "${arch}-windres" "echo $@; PATH=${cc}/bin/ ${cc}/bin/${arch}-windres $@"}";
        ranlib = "${cc}/bin/${arch}-ranlib";
        ar = "${cc}/bin/${arch}-ar";
        cCompiler = "${cc}/bin/${arch}-gcc";
        cppCompiler = "${cc}/bin/${arch}-c++";
        toolchain = pkgs.writeTextFile {
          name = "${arch}.cmake-toolchain";
          text = ''
            set(CMAKE_SYSTEM_NAME Windows)
            set(CMAKE_SYSTEM_PROCESSOR x86_64)
            set(CMAKE_HOST_SYSTEM_NAME Linux)
            set(CMAKE_HOST_SYSTEM_PROCESSOR x86_64)
            set(CMAKE_CROSSCOMPILING ON)
            set(CMAKE_BUILD_TYPE RelWithDebInfo)
            # search for programs in the build host directories
            set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
            # for libraries and headers in the target directories
            set(CMAKE_PLATFORM_NO_VERSIONED_SONAME ON)
            set(DLL_NAME_WITH_SOVERSION OFF)
            set(CMAKE_DLL_NAME_WITH_SOVERSION OFF)
            set(CMAKE_SHARED_LIBRARY_NAME_WITH_VERSION OFF)
            set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
            set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
            set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
            set(CMAKE_FIND_ROOT_PATH
              "${cc}")

            set(CMAKE_C_COMPILER "${cCompiler}")
            set(CMAKE_CXX_COMPILER "${cppCompiler}")
            set(CMAKE_AR "${ar}" CACHE FILEPATH "ar")
            set(CMAKE_RANLIB "${ranlib}" CACHE FILEPATH "ranlib")
            set(CMAKE_WINDRES "${windres}" CACHE FILEPATH "windres")
            set(CMAKE_RC_COMPILER "${windres}" CACHE FILEPATH "windres")

            # some projects use this as an unofficial variable for windows versions
            set(windows-version ${winNt})
          '';
        };
        cmakeFlags = lib.concatStringsSep " " [
          "-D_WIN32_WINNT=${winNt}"
          "-DWINVER=${winNt}"
          "-DCMAKE_TOOLCHAIN_FILE=${toolchain}"
        ];
        exports = let
          CFLAGS = lib.concatStringsSep " " ([
              "-DWINVER=${winNt}"
              "-D_WIN32_WINNT=${winNt}"
              "-static-libgcc"
              "-static"
            ]
            ++ activeMatrix.CFLAGS);
          CXXFLAGS = CFLAGS + " -static-libstdc++";
          LDFLAGS = lib.concatStringsSep " " ([
              "-DWINVER=${winNt}"
              "-D_WIN32_WINNT=${winNt}"
            ]
            ++ activeMatrix.LDFLAGS);
        in
          lib.concatStringsSep " " [
            "PATH=\"$PATH:${stdenvWin32Threads.cc}/bin\""
            "CFLAGS=\"$CFLAGS ${CFLAGS}\""
            "CXXFLAGS=\"$CXXFLAGS ${CXXFLAGS}\""
            "LDFLAGS=\"$CFLAGS ${LDFLAGS}\""
            "CC='${cCompiler}'"
            "CXX='${cppCompiler}'"
            "LD='${ld}'"
            "AR='${ar}'"
            "RANLIB='${ranlib}'"

            "RC='${windres}'"
          ];
      in "${exports} ${crossPkgs.buildPackages.cmake}/bin/cmake ${cmakeFlags}";
    };
    ld = "${crossPkgs.buildPackages.gcc}/bin/${arch'}-${vendor}-${sys}-ld";
    as = "${crossPkgs.buildPackages.gcc}/bin/${arch'}-${vendor}-${sys}-as";
  in
    lib.recursiveUpdate
    {
      infoAttrs = mkMingwArch arch' vendor sys fpcTarget fpcCpu fpcBasename as ld chosenMatrix;
      inherit fmodex;
    }
    set;
  mkMingwArch = arch: vendor: sys: fpcTarget: fpcCpu: fpcBasename: as: ld: matrix: {
    caseSensitive = false;
    d2dforeverFeaturesSuport = {
      openglDesktop = true;
      openglEs = true;
      supportsHeadless = true;
      loadedAsLibrary = false;
    };
    isWindows = true;
    majorPlatform = "windows";
    bundleFormats = ["zip"];
    bundle = let
      bundleMatrix = {
        win32Threads = {
          io = "SDL2";
          sound = "FMOD";
          graphics = "OpenGL2";
          headless = "Disable";
          holmes = "Enable";
          assets.midiBank = "native";
        };
        mcfgthread = {
          io = "SDL2";
          sound = "OpenAL";
          graphics = "OpenGL2";
          headless = "Disable";
          holmes = "Enable";
          assets.midiBank = "soundfont";
        };
      };
    in
      bundleMatrix.${matrix};
    fpcAttrs = rec {
      lazarusExists = true;
      cpuArgs = [];
      wrapperArgs = ["-O1" "-g" "-gl"];
      targetArg = "-T${fpcTarget}";
      basename = fpcBasename;
      makeArgs = {
        OS_TARGET = fpcTarget;
        CPU_TARGET = fpcCpu;
        CROSSOPT = "\"" + (lib.concatStringsSep " " cpuArgs) + "\"";
      };
      toolchainPaths = [
        "${pkgs.writeShellScriptBin "${fpcCpu}-${fpcTarget}-as" "${as} $@"}/bin"
        "${pkgs.writeShellScriptBin "${fpcCpu}-${fpcTarget}-ld" "${ld} $@"}/bin"
      ];
    };
  };
in {
  mingw32 = lib.removeAttrs (mkMingwCrossPkg "i686" "w64" "mingw32" "mingw32" "win32" "i386" "cross386" "win32Threads") ["openal" "fluidsynth"];
  mingw64 = mkMingwCrossPkg "x86_64" "w64" "mingw32" "mingwW64" "win64" "x86_64" "crossx64" "mcfgthread";
}
