args @ {
  stdenv,
  callPackage,
  jdk17,
  jdk8,
  _7zz,
  openssl,
  findutils,
  coreutils-full,
  file,
  androidSdk,
  lib,
  SDL2ForJava,
  androidRoot,
  mkAndroidManifest,
  androidPlatform,
  androidIcons,
  versionExtraPrefix ? "",
  assets,
  executables,
  licenses ? null,
}:
stdenv.mkDerivation (finalAttrs: let
  ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
  ANDROID_JAR = "${ANDROID_HOME}/platforms/android-34/android.jar";
  aapt = "${ANDROID_HOME}/build-tools/28.0.3/aapt";
  jdk = jdk17;
  jdkSign = jdk8;
  d8 = "${ANDROID_HOME}/build-tools/35.0.0/d8";
  apksigner = "${ANDROID_HOME}/build-tools/35.0.0/apksigner";
  zipalign = "${ANDROID_HOME}/build-tools/35.0.0/zipalign";
  androidManifest = callPackage mkAndroidManifest {
    packageName = "org.d2df.app";
    versionName = "0.667b${versionExtraPrefix}";
    minSdkVersion = androidPlatform;
    targetSdkVersion = "34";
    glEsVersion = "0x00010001";
  };
in {
  version = "0.667-git";
  pname = "d2df-apk";
  name = "${finalAttrs.pname}-${finalAttrs.version}";

  nativeBuildInputs = [findutils jdk coreutils-full file openssl _7zz];

  src = androidRoot;

  buildPhase =
    # Precreate directories to be used in the build process.
    ''
      mkdir -p bin obj gen res
      mkdir -p resources aux/lib
      mkdir -p src/org/libsdl/app/
    ''
    + (''
        cp -r ${androidIcons}/* res
        cp ${androidManifest} AndroidManifest.xml
      ''
      + ''
        7zz x -mtm -ssp -y ${assets} -oresources
        7zz x -mtm -ssp -y ${executables} -oaux/lib
      ''
      + lib.optionalString (!builtins.isNull licenses) ''
        7zz x -mtm -ssp -y ${licenses} -oresources
      '')
    # Use SDL Java sources from the version we compiled our game with.
    + ''
      cp -r "${SDL2ForJava.src}/android-project/app/src/main/java/org/libsdl/app" "src/org/libsdl"
    ''
    # Build the APK.
    + ''
      ${aapt} package -f -m -S res -J gen -M AndroidManifest.xml -I ${ANDROID_JAR}
      ${jdkSign}/bin/javac -encoding UTF-8 -source 1.8 -target 1.8 -classpath "${ANDROID_JAR}" -d obj gen/org/d2df/app/R.java $(find src -name '*.java')
      ${d8} $(find obj -name '*.class') --lib ${ANDROID_JAR} --release --min-api ${androidPlatform} --android-platform-build --output bin/classes.jar
      ${d8} ${ANDROID_JAR} bin/classes.jar --release --min-api ${androidPlatform} --android-platform-build --output bin
      ${aapt} package -f -M ./AndroidManifest.xml -S res -I ${ANDROID_JAR} -F bin/d2df.unsigned.apk -A resources bin aux
      ${zipalign} -v -f -p 4 "bin/d2df.unsigned.apk" "bin/d2df.unsigned.aligned.apk"
      openssl req -x509 -subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=example.com" -nodes -days 10000 -newkey rsa:2048 -keyout keyfile.pem -out certificate.pem
      openssl pkcs12 -export -in certificate.pem -inkey keyfile.pem -out my_keystore.p12 -passout "pass:" -name my_key
      ${apksigner} sign --ks my_keystore.p12 --ks-pass "pass:" --out bin/d2df.signed.aligned.apk bin/d2df.unsigned.aligned.apk
    '';

  installPhase = ''
    cp bin/d2df.signed.aligned.apk $out
  '';
})
