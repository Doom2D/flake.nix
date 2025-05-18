{
  lib,
  fetchFromGitHub,
  rustPlatform,
  src,
}:
rustPlatform.buildRustPackage rec {
  pname = "dfwad";
  version = "v0.1.0";
  buildType = "debug";

  inherit src;

  cargoHash = "sha256-4G092Kfl0N0FXhgRYBTMT50iZ+eZPMKDrjaift1QDnU=";

  meta = {
    description = "Manage your DFWADs, extract and create them.";
    homepage = "https://github.com/poybluez/dfwad";
    license = lib.licenses.mit0;
  };
}
