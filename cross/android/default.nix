{
  lib,
  pkgs,
  pins,
}: let
  buildToolsVersion = "35.0.0";
  cmakeVersion = "3.22.1";
  ndkVersion = "17.2.4988734";
  ndkBinutilsVersion = "22.1.7171670";
  platformToolsVersion = "35.0.2";
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [buildToolsVersion "28.0.3"];
    inherit platformToolsVersion;
    platformVersions = ["34" "31" "28" "21" "16" "14" "9"];
    abiVersions = ["armeabi-v7a" "arm64-v8a"];
    cmakeVersions = [cmakeVersion];
    includeNDK = true;
    ndkVersions = [ndkVersion ndkBinutilsVersion];

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

  #mkArch = androidAbi: clangTriplet: name: fpcCpu: fpcFloat: basename: androidPlatform: let
  mkArch = args @ {
    androidNativeBundleAbi,
    clangTriplet,
    compiler,
    name,
    CPU_TARGET,
    fpcCpu,
    fpcFloat,
    basename,
    isOldNdk ? false,
    ndkOldArch ? null,
    targetArg ? [],
    androidPlatform,
  }: let
    sysroot = "${androidNdk}/toolchains/llvm/prebuilt/linux-x86_64/sysroot";
    ndkLib =
      if !isOldNdk
      then "${sysroot}/usr/lib/${clangTriplet}/${androidPlatform}"
      else "${androidNdk}/platforms/android-${androidPlatform}/arch-${ndkOldArch}/usr/lib";
    ndkToolchain =
      if !isOldNdk
      then "${androidNdk}/toolchains/llvm/prebuilt/linux-x86_64/bin"
      else "${androidNdk}/toolchains/${clangTriplet}-4.9/prebuilt/linux-x86_64/bin";
    ndkBinutilsToolchain = "${androidNdkBinutils}/toolchains/llvm/prebuilt/linux-x86_64/bin";
    binutilsPrefix =
      if !isOldNdk
      then "${androidNdkBinutils}/toolchains/llvm/prebuilt/linux-x86_64/${clangTriplet}/bin/"
      else "${ndkToolchain}/${clangTriplet}-";
    pretty = "Android ${androidNativeBundleAbi}, platform level ${androidPlatform}, NDK ${ndkVersion}";
  in rec {
    inherit androidNativeBundleAbi;
    isAndroid = true;
    isWindows = false;
    bundleFormats = ["apk"];
    caseSensitive = true;
    d2dforeverFeaturesSuport = {
      openglDesktop = false;
      openglEs = true;
      supportsHeadless = false;
      loadedAsLibrary = true;
    };
    fpcAttrs = let
      cpuArgs = ["-Cp${fpcCpu}" "-Cf${fpcFloat}" "-Fl${ndkLib}" "-XP${binutilsPrefix}"];
    in {
      lazarusExists = false;
      inherit cpuArgs;
      targetArg = "-Tandroid" + " " + (lib.concatStringsSep " " targetArg);
      wrapperArgs = ["-O1" "-g" "-gl"];
      basename = basename;
      makeArgs = {
        OS_TARGET = "android";
        CPU_TARGET = CPU_TARGET;
        CROSSOPT = "\"" + (lib.concatStringsSep " " cpuArgs) + "\"";
        NDK = "${androidNdk}";
      };
      toolchainPaths = [
        ndkToolchain
        ndkBinutilsToolchain
      ];
    };
  };

  mkCrossPkg = args @ {
    androidNativeBundleAbi,
    clangTriplet,
    name,
    compiler,
    CPU_TARGET,
    fpcCpu,
    fpcFloat,
    basename,
    targetArg,
    isOldNdk ? false,
    ndkOldArch ? false,
    androidPlatform,
  }: let
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
    common = import ../_common {
      inherit lib pkgs pins;
      arch = androidNativeBundleAbi;
      cmake = let
        cmakeFlags = lib.concatStringsSep " " (
          [
            (lib.optionalString (!isOldNdk) "-DCMAKE_POLICY_DEFAULT_CMP0057=NEW")
            "-DCMAKE_TOOLCHAIN_FILE=${androidNdk}/build/cmake/android.toolchain.cmake"
            "-DANDROID_ABI=${androidNativeBundleAbi}"
            "-DANDROID_PLATFORM=android-${androidPlatform}"
            "-DANDROID_NDK=${androidNdk}"
            "-DANDROID_STL=c++_static"
            "-DCMAKE_BUILD_TYPE=Release"
          ]
          #++ lib.optionals (CPU_TARGET == "arm") ["-DANDROID_ARM_NEON=FALSE"]
        );
      in "${lib.optionalString isOldNdk "export LD_LIBRARY_PATH=\"${ncursesFixed}/lib\";"} ${pkgs.cmake}/bin/cmake ${cmakeFlags}";
    };
  in
    lib.recursiveUpdate
    common {
      infoAttrs = mkArch args;
      inherit androidSdk androidPlatform;
      openal = common.openal.overrideAttrs (finalAttrs: prevAttrs: {
        version = pins.openal_android.version;
        src = pins.openal_android.src;
      });
    };
in {
  arm64-v8a-linux-android = mkCrossPkg {
    androidNativeBundleAbi = "arm64-v8a";
    name = "android-arm64-v8a";
    clangTriplet = "aarch64-linux-android";
    compiler = "aarch64-linux-android";
    CPU_TARGET = "aarch64";
    basename = "crossa64";
    fpcCpu = "ARMV8";
    fpcFloat = "VFP";
    isOldNdk = true;
    ndkOldArch = "arm64";
    targetArg = [];
    androidPlatform = let
      int = lib.strings.toInt androidPlatform;
    in
      if int < 21
      then "21"
      else androidPlatform;
  };

  armeabi-v7a-linux-android = mkCrossPkg {
    androidNativeBundleAbi = "armeabi-v7a";
    name = "armv7a-linux-androideabi";
    clangTriplet = "arm-linux-androideabi";
    compiler = "armv7a-linux-androideabi";
    CPU_TARGET = "arm";
    basename = "crossarm";
    fpcCpu = "ARMV7A";
    fpcFloat = "VFPV3";
    isOldNdk = true;
    ndkOldArch = "arm";
    targetArg = ["-CfVFPV3_D16" "-CaEABI"];
    androidPlatform = let
      int = lib.strings.toInt androidPlatform;
    in
      if int < 5
      then "5"
      else androidPlatform;
  };
}
