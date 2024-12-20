{
  default = {
    pkgs,
    lib,
    fpcPkgs,
    d2dfPkgs,
    mkGameBundle,
    gameAssetsPath,
    d2df-sdl,
    doom2df-res,
    d2df-editor,
  }: let
    mingwPkgs = import ../cross/mingw {
      inherit pkgs lib;
      inherit d2df-sdl doom2df-res d2df-editor;
      inherit fpcPkgs d2dfPkgs;
    };
    byArchAdditional =
      lib.mapAttrs (target: targetAttrs: let
        doom2df-bundle = mkGameBundle {
          inherit gameAssetsPath;
          unknownPkgsAttrs = {
            sharedBundledLibraries = [targetAttrs.enet targetAttrs.SDL2 targetAttrs.fmodex];
            doom2df = targetAttrs.doom2d;
            editor = targetAttrs.editor;
          };
          isWindows = true;
          withEditor = true;
        };
      in {
        inherit doom2df-bundle;
      })
      mingwPkgs.byArch;
    universalAdditional = rec {
    };
  in
    lib.recursiveUpdate mingwPkgs {
      byArch = byArchAdditional;
      universal = universalAdditional;
    };

  # Maybe WIN95 support or something...
  /*
  old = ...;
  */
}
