{
  # Example:
  # {"arm64-v8a" = { isWindows = false; sharedLibraries = [SDL2_custom enet_custom]; doom2df = .../null; editor = .../null; asLibrary = false; prefix = "arm64-v8a"}; }
  byArchPkgsAttrs,
  stdenvNoCC,
  withDates ? false,
  gameDate ? null,
  editorDate ? null,
  withHeadless ? false,
  asZip ? true,
  gnused,
  gawk,
  zip,
  findutils,
  outils,
  _7zz,
  lib,
  coreutils,
}:
stdenvNoCC.mkDerivation {
  pname = "d2df-executable-path";
  version = "git";
  phases = ["buildPhase" "installPhase"];

  src = null;

  dontPatchELF = true;
  dontStrip = true;
  dontFixup = true;
  dontShrink = true;

  nativeBuildInputs = [gawk gnused zip findutils outils coreutils _7zz];

  buildPhase = let
    script = date: suffix: needsSuffix: archAttrs: let
      suffix' = lib.optionalString (needsSuffix && archAttrs.isWindows) suffix;
    in ''      \
            TARGET=${archAttrs.prefix}/''${0##*/}${suffix'}; \
            cp $0 $TARGET; \
            ${lib.optionalString withDates "touch -d \"${date}\" $TARGET"}'';
    copyLibraries = archAttrs: let
      i =
        lib.map (library: ''
          find -L ${library}/ -type f \( -iname '*.so' -or -iname '*.dll' -or -iname '*.dylib' \) \
          -exec sh -c '${script gameDate "" false archAttrs}' {} \;
        '')
        archAttrs.sharedLibraries;
    in
      lib.concatStringsSep "\n" (i
        ++ [
          "mv ${archAttrs.prefix}/libogg.dll ${archAttrs.prefix}/ogg.dll || :"
          "find -L ${archAttrs.prefix} -iname 'libsyn123*' -type f -exec rm {} +"
          "find -L ${archAttrs.prefix} -iname 'libvorbisenc*' -type f -exec rm {} +"
        ]);
    copyGameAndEditor = archAttrs: (
      lib.optionalString (!builtins.isNull archAttrs.doom2df)
      (
        if archAttrs.asLibrary
        then ''
          [ -d "${archAttrs.doom2df}/lib" ] && find -L ${archAttrs.doom2df}/lib -type f \
             -exec sh -c '${script gameDate ".exe" false archAttrs}' {} \;
        ''
        else
          ''
            find -L ${archAttrs.doom2df}/bin -type f \
               -exec sh -c '${script gameDate ".exe" true archAttrs}' {} \;
          ''
          + lib.optionalString (archAttrs.withHeadless or false) ''
            find -L ${archAttrs.doom2dfHeadless}/bin -type f \
               -exec sh -c '${script gameDate ".exe" true archAttrs}' {} \;
          ''
      )
      + (
        lib.optionalString (!builtins.isNull archAttrs.editor)
        ''
          [ -d "${archAttrs.editor}/bin" ] && find -L ${archAttrs.editor}/bin -type f \
             -exec sh -c '${script editorDate ".exe" true archAttrs}' {} \;
        ''
      )
    );
    copyEachArch = arch: archAttrs: ''
      mkdir -p "${archAttrs.prefix}"
      ${copyLibraries archAttrs}
      ${copyGameAndEditor archAttrs}
    '';
  in ''
    mkdir -p build
    cd build
    ${lib.concatStringsSep "\n" (lib.map (x: copyEachArch x.name x.value) (lib.attrsToList byArchPkgsAttrs))}
  '';

  installPhase =
    if asZip
    then ''
      cd /build
      7zz a -y -mtm -ssp -tzip out.zip -w build/.
      mv out.zip $out
    ''
    else ''
      cd /build
      mkdir -p $out
      cp build/* $out
    '';

  meta = {
    arches = byArchPkgsAttrs;
    licenses = let
      getLibraries = arch: arch.sharedLibraries ++ [arch.doom2df];
      all = lib.foldl (acc: cur: acc ++ (getLibraries cur)) [] (lib.attrValues byArchPkgsAttrs);
      files =
        lib.map (x: {
          inherit (x) pname;
          license = x.meta.licenseFiles or [];
        })
        all;
    in
      files;
  };
}
