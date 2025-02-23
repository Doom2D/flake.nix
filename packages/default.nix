{
  lib,
  pins,
  defaultAssetsPath,
  callPackage,
  executablesAttrs,
  mkExecutablePath,
  mkGamePath,
  mkZip,
  mkApple,
  mkLicenses,
  mkAndroidApk,
  androidRoot,
  androidIcons,
  macOsIcns,
  mkAndroidManifest,
  d2df-distro-content,
  d2df-distro-soundfont,
}: let
  createAllPossibleExecutables = "";
  createAllCombos = arch: archAttrs: let
    info = archAttrs.infoAttrs.d2dforeverFeaturesSuport;
    features = {
      io = {
        SDL1 = archAttrs: archAttrs ? "SDL1";
        SDL2 = archAttrs: archAttrs ? "SDL2";
        sysStub = archAttrs: info.supportsHeadless;
      };
      graphics = {
        OpenGL2 = archAttrs: info.openglDesktop;
        OpenGLES = archAttrs: info.openglEs;
        GLStub = archAttrs: info.supportsHeadless;
      };
      sound = {
        FMOD = archAttrs: archAttrs ? "fmodex";
        SDL_mixer = archAttrs: archAttrs ? "SDL_mixer";
        SDL2_mixer = archAttrs: archAttrs ? "SDL2_mixer";
        OpenAL = archAttrs: archAttrs ? "openal";
        NoSound = archAttrs: true;
      };
      headless = {
        Enable = archAttrs: info.supportsHeadless;
        Disable = archAttrs: true;
      };
      holmes = {
        Enable = archAttrs: info.openglDesktop;
        Disable = archAttrs: true;
      };
    };
    featuresMatrix = features: archAttrs: let
      prepopulatedFeatureAttrs = lib.mapAttrs (featureName: featureAttrs: (lib.mapAttrs (definition: value: (value archAttrs) == true)) featureAttrs) features;
      filteredFeatureAttrs = lib.mapAttrs (featureName: featureAttrs: (lib.filterAttrs (definition: value: value == true) featureAttrs)) prepopulatedFeatureAttrs;
      zippedFeaturesWithPossibleValues = lib.mapAttrs (feature: featureAttrset: (lib.foldlAttrs (acc: definitionName: definitionValue: acc ++ [definitionName]) [] featureAttrset)) filteredFeatureAttrs;
      featureCombinations = lib.cartesianProduct zippedFeaturesWithPossibleValues;
    in
      # TODO
      # Get some filters here.
      # Maybe sound == SDL2 && io != SDL2?
      lib.filter (
        combo:
          !(
            (combo.holmes == "Enable" && combo.graphics != "OpenGL2")
            || (combo.holmes == "Enable" && combo.io != "SDL2")
            || (combo.graphics == "OpenGLES" && combo.io != "SDL2")
            # FIXME
            # SDL1 is not packaged yet
            || (combo.io == "SDL1")
            #|| (combo.sound == "FMOD")
            #|| (combo.io == "sysStub" && combo.headless == "disable")
            || (combo.sound == "SDL2_mixer" && combo.io != "SDL2")
            || (combo.sound == "SDL_mixer" && combo.io != "SDL1")
          )
      )
      featureCombinations;
    mkExecutable = doom2d: featureAttrs @ {
      graphics,
      headless,
      io,
      sound,
      holmes,
    }: let
      ioFeature = let
        table = {
          "SDL1" = {withSDL1 = true;};
          "SDL2" = {withSDL2 = true;};
          "sysStub" = {disableIo = true;};
        };
      in
        table.${io};
      graphicsFeature = let
        table = {
          "OpenGL2" = {withOpenGL2 = true;};
          "OpenGLES" = {withOpenGLES = true;};
          "GLStub" = {disableGraphics = true;};
        };
      in
        table.${graphics};
      soundFeature = let
        table = {
          "FMOD" = {withFmod = true;};
          "SDL_mixer" = {withSDL1_mixer = true;};
          "SDL2_mixer" = {withSDL2_mixer = true;};
          "OpenAL" = {
            withOpenAL = true;
            withVorbis = true;
            # FIXME
            # mingw doesn't have working fluidsynth
            withFluidsynth = true;
            withLibXmp = true;
            withMpg123 = true;
            withOpus = true;
            withGme = true;
          };
          "NoSound" = {disableSound = true;};
        };
      in
        table."${sound}";
      boolFeature = flag: x:
        if x == "Enable"
        then {"${flag}" = true;}
        else {"${flag}" = false;};
      headlessFeature = boolFeature "headless" headless;
      holmesFeature = boolFeature "holmes" holmes;
    in {
      value = {
        drv = doom2d.override ({
            inherit headless;
            buildAsLibrary = info.loadedAsLibrary;
          }
          // ioFeature
          // graphicsFeature
          // soundFeature
          // headlessFeature
          // holmesFeature);
        defines = {
          inherit graphics headless sound holmes io;
        };
      };
      name = let
        soundStr =
          if sound == "disable"
          then "-NoSound"
          else "-${sound}";
        ioStr =
          if io == "sysStub"
          then "-IOStub"
          else "-${io}";
        graphicsStr = "-${graphics}";
        headlessStr = lib.optionalString (headless == "Enable") "-headless";
        holmesStr = lib.optionalString (holmes == "Enable") "-holmes";
      in "doom2df-${arch}${ioStr}${soundStr}${graphicsStr}${headlessStr}${holmesStr}";
    };
    matrix = featuresMatrix features archAttrs;
    allCombos = lib.listToAttrs (lib.map (x: mkExecutable archAttrs.doom2d x) matrix);
  in
    allCombos;
  createBundlesAndExecutables = lib.mapAttrs (arch: archAttrs: let
    createCombos = arch: archAttrs: createAllCombos arch archAttrs;
    createBundles = arch: archAttrs: let
      info = archAttrs.infoAttrs;
      allCombos = createAllCombos arch archAttrs;
      defaultExecutable = ((builtins.head (lib.attrValues (lib.filterAttrs (n: v: v.defines == archAttrs.infoAttrs.bundle) allCombos))).drv).override {
        withMiniupnpc = true;
      };
      assets = defaultAssetsPath.override {
        withEditor = !builtins.isNull archAttrs.editor;
        toLower = archAttrs.infoAttrs.caseSensitive;
        flexuiDistro = true;
        withDistroContent = true;
        distroContent = d2df-distro-content;
        distroMidiBanks = d2df-distro-soundfont;
        withDistroGus = true;
      };
      executables = callPackage mkExecutablePath rec {
        byArchPkgsAttrs = {
          "${arch}" = {
            sharedLibraries = lib.map (drv: drv.out) defaultExecutable.buildInputs;
            doom2df = defaultExecutable;
            editor = archAttrs.editor;
            isWindows = archAttrs.infoAttrs.isWindows;
            asLibrary = info.loadedAsLibrary or false;
            prefix = ".";
          };
        };
      };
      licenses = callPackage mkLicenses {inherit assets executables;};
      zip = let
        zip = callPackage mkZip {inherit assets executables licenses;};
      in
        if (lib.lists.elem "zip" archAttrs.infoAttrs.bundleFormats)
        then zip
        else null;
      apple = let
        apple = callPackage mkApple {inherit assets executables licenses macOsIcns;};
      in
        if (lib.lists.elem "apple" archAttrs.infoAttrs.bundleFormats)
        then apple
        else null;
    in
      lib.filterAttrs (n: v: !builtins.isNull v) {
        inherit zip apple;
      };
  in {
    __archPkgs = archAttrs;
    allCombos = createCombos arch archAttrs;
    bundles = createBundles arch archAttrs;
  });

  mkAndroid = executablesAttrs: let
    elem = lib.last (lib.attrValues (lib.filterAttrs (n: v: lib.hasSuffix "android" n) executablesAttrs));
    # FIXME
    # Just find something with "android" as prefix instead of hardcoding it
    sdk = elem.androidSdk;
    sdl = elem.SDL2;
    androidPlatform = elem.androidPlatform;
    gameExecutablePath = callPackage mkExecutablePath {
      byArchPkgsAttrs =
        lib.mapAttrs (arch: archAttrs: let
          doom2d = archAttrs.doom2d.override {
            withSDL2 = true;
            withSDL2_mixer = true;
            withVorbis = true;
            withLibXmp = true;
            withMpg123 = true;
            withOpus = true;
            withGme = true;
            withOpenGLES = true;
            buildAsLibrary = true;
          };
        in {
          sharedLibraries = lib.map (drv: drv.out) doom2d.buildInputs;
          # FIXME
          # Android version is hardcoded
          doom2df = doom2d;
          isWindows = false;
          asLibrary = true;
          editor = null;
          prefix = "${archAttrs.infoAttrs.androidNativeBundleAbi}";
        })
        (lib.filterAttrs (n: v: lib.hasSuffix "android" n) executablesAttrs);
    };
  in {
    android = let
      assets = defaultAssetsPath.override {
        withEditor = false;
        toLower = true;
        withDistroContent = true;
        flexuiDistro = false;
        distroContent = d2df-distro-content;
        distroMidiBanks = d2df-distro-soundfont;
        withDistroGus = true;
      };
      executables = gameExecutablePath;
      licenses = callPackage mkLicenses {inherit assets executables;};
    in {
      bundles = rec {
        default = callPackage mkAndroidApk {
          androidSdk = sdk;
          SDL2ForJava = sdl;
          inherit assets executables licenses;
          inherit androidRoot androidIcons androidPlatform mkAndroidManifest;
        };
      };
      allCombos = {};
    };
  };
in
  (createBundlesAndExecutables executablesAttrs)
  // (mkAndroid executablesAttrs)
