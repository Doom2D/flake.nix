{
  lib,
  callPackage,
  stdenv,
  writeText,
  DF-Assets,
  d2df-editor,
  buildWad,
  dfw-rs,
  mkAssetsPath,
}: rec {
  wads = lib.listToAttrs (lib.map (wad: {
      name = wad.out;
      value = callPackage buildWad {
        srcFolder = wad.srcFolder;
        outName = wad.out;
        normalizeBlacklist = wad.normalizeBlacklist or [];
        lstPath = "${wad.out}.lst";
        dfwadCompression = "best";
        inherit DF-Assets;
        inherit dfw-rs;
      };
    }) [
      {
        out = "game";
        srcFolder = "GameWAD";
        shouldNormalize = true;
        # Leave these quiet, as they are very annoying
        normalizeBlacklist = ["CASING1.wav" "CASING2.wav" "BUBBLE1.wav" "BUBBLE2.wav" "BURNING.wav" "SHELL1.wav" "SHELL2.wav"];
      }
      {
        out = "editor";
        srcFolder = "EditorWAD";
      }
      {
        out = "shrshade";
        srcFolder = "ShrShadeWAD";
      }
      {
        out = "standart";
        srcFolder = "StandartWAD";
      }
      {
        out = "doom2d";
        srcFolder = "Doom2DWAD";
      }
      {
        out = "doomer";
        srcFolder = "DoomerWAD";
        shouldNormalize = true;
      }
    ]);
  defaultAssetsPath = mkAssetsPath.override {
    doom2dWad = wads.doom2d;
    doomerWad = wads.doomer;
    standartWad = wads.standart;
    shrshadeWad = wads.shrshade;
    gameWad = wads.game;
    editorWad = wads.editor;
    editorLangRu = "${d2df-editor}/lang/editor.ru_RU.lng";
    botlist = "${DF-Assets}/plain/botlist.txt";
    botnames = "${DF-Assets}/plain/botnames.txt";
    extraRoots = let
      mkTxtFile = name': txt:
        stdenv.mkDerivation {
          name = lib.replaceStrings [" "] ["_"] name';

          src = null;
          phases = ["installPhase"];

          installPhase = ''
            mkdir $out
            cp ${writeText "${name'}" txt} "$out/${name'}"
          '';
        };
      findMoreContentTxt = mkTxtFile "Get MORE game content HERE.txt" ''
        Дополнительные уровни и модели игрока можно скачать на https://doom2d.org
        You can download additional maps or user skins on our website: https://doom2d.org
      '';
    in [findMoreContentTxt];
  };
}
