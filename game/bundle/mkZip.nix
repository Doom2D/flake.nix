{
  stdenv,
  executables,
  assets,
  licenses ? null,
  lib,
  _7zz,
  symlinkJoin,
  macdylibbundler,
  rcodesign,
  findutils,
  asZip ? true,
}: let
  first = (lib.head (lib.attrsToList executables.meta.arches)).value;
  isDarwin = first.majorPlatform == "macOS";
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "d2df-zip-bundle";
    version = "0.667";

    buildInputs = [_7zz] ++ lib.optionals isDarwin [macdylibbundler rcodesign findutils];

    nativeBuildInputs = [first.doom2df.buildInputs];

    src = null;

    dontUnpack = true;

    buildPhase =
      ''
        mkdir -p build
        7zz x -mtm -ssp -y ${assets} -obuild
      ''
      + (
        if isDarwin
        then ''
          TMP=$(mktemp -d)
          7zz x -mtm -ssp -y ${executables} -o$TMP
          cp $TMP/Doom2DF build/
          cd $TMP
          dylibbundler -ns -of -b \
            -s $TMP \
            -d /build/build -p '@executable_path/' -x /build/build/Doom2DF
          cd -
        ''
        else ''
          7zz x -mtm -ssp -y ${executables} -obuild
        ''
      )
      + lib.optionalString (!builtins.isNull licenses) "7zz x -mtm -ssp -y ${licenses} -obuild";

    installPhase =
      ''
        cd /build
      ''
      + lib.optionalString isDarwin ''
        rcodesign sign build/Doom2DF
        find build -iname '*.dylib' -exec rcodesign sign {} \;
      ''
      + (
        if asZip
        then ''
          7zz a -y -mtm -ssp -tzip out.zip -w build/.
          mv out.zip $out
        ''
        else ''
          mv build/ $out
        ''
      );

    meta.mainProgram = "Doom2DF";
  })
