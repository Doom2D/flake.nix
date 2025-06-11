let
  standard = ./scripts/parse.awk;
  normalizerPath = ./scripts/normalize.bash;
in {
  buildWadScript = standard;
  buildWad = {
    outName ? "game",
    srcFolder ? "GameWAD",
    lstPath ? "game.lst",
    lib,
    DF-Assets,
    buildWadScript ? standard,
    stdenvNoCC,
    gnused,
    gawk,
    convmv,
    coreutils,
    util-linux,
    bash,
    dos2unix,
    dfwad,
    dfwadCompression ? "none",
    shouldNormalize ? true,
    normalizeBlacklist ? [],
    parallel,
    findutils,
    ffmpeg,
    ffmpeg-normalize,
    ripgrep,
    writeShellScript,
  }: let
  normalizer = writeShellScript "normalizer" (builtins.readFile normalizerPath); in
    stdenvNoCC.mkDerivation {
      pname = "d2df-${outName}-wad";
      version = "git";

      dontStrip = true;
      dontPatchELF = true;
      dontFixup = true;

      nativeBuildInputs =
        [bash gawk gnused convmv dfwad coreutils util-linux dos2unix]
        ++ lib.optionals shouldNormalize [
          parallel
          findutils
          ffmpeg
          ffmpeg-normalize
          ripgrep
        ];

      src = DF-Assets;

      buildPhase =
        # FIXME
        # Script should be able to support arbitrary paths, not just in the current directory
        # FIXME
        # For some reason, shrshade.lst specifies the source folder in lowercase.
        # This doesn't fly in Linux.
        # FIXME
        # dos line endings have to be forced, because game doesn't recognize lf lines
        ''
          set -euo pipefail
          echo "Force dos line endings for all files in this repo"
          find . -type f -exec unix2dos {} \;
          echo "Fixing dos line endings"
          dos2unix ${lstPath}
          echo "Fixing shrshade.wad paths"
          sed -i 's\shrshadewad\ShrShadeWAD\g' shrshade.lst
        ''
        + lib.optionalString shouldNormalize (
          # Sounds we should make more quiet
          ''
          find ${srcFolder} -type f \( -iname '*.mp3' -or -iname '*.wav' \) \
           ${lib.optionalString (normalizeBlacklist != []) " | grep " + (lib.concatStringsSep " "
             (lib.map (x: "-e ${x}") normalizeBlacklist))} \
           | parallel -j32 ${normalizer} {} -23.0 \;
        '' +
          # All other sounds
        ''
          find ${srcFolder} -type f \( -iname '*.mp3' -or -iname '*.wav' \) \
           ${lib.optionalString (normalizeBlacklist != []) " | grep -v " + (lib.concatStringsSep " "
             (lib.map (x: "-e ${x}") normalizeBlacklist))} \
           | parallel -j32 ${normalizer} {} -5.0 \;
        '')
        + ''
          mkdir -p temp
          chmod -R 777 temp
          echo "Moving files from ${lstPath} to dfwad suitable directory"
          ${gawk}/bin/awk -f ${buildWadScript} -v prefix="temp" ${lstPath}
          # For some reason, this AWK script sets wrong perms
          chmod -R 777 temp
          echo "Converting win1251 names to UTF-8"
          convmv -f CP1251 -t UTF-8 --notest -r temp
          echo "Removing extensions from nested wads"
          find temp -mindepth 4 -type f -exec bash -c '
                     WITHOUT_EXT=$(basename $1 | rev | cut -f 2- -d '.' | rev);
                     echo "moving $1 to $(dirname $1)/$WITHOUT_EXT";
                     mv "$1" "$(dirname $1)/$WITHOUT_EXT";
                     ' bash {} \;
          echo "Calling dfwad"
          dfwad -v -z "${dfwadCompression}" temp/ ${outName}.wad pack
        '';

      installPhase = ''
        mv "${outName}.wad" $out
      '';
    };
}
