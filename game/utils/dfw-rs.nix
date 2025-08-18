{
  lib,
  fetchFromGitHub,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "dfw-rs";
  version = "0-unstable-2025-07-24";

  src = fetchFromGitHub {
    owner = "Doom2D";
    repo = "dfw-rs";
    rev = "872cf4126d94a430fdae20824b421dc0f43dd3d2";
    sha256 = "sha256-rr6S95NLN5DyJXLrdOWOjFFcrGxy+MMw53HDuJ6PM7k=";
  };

  cargoHash = "sha256-8okZflfFjtLSHmQ8uU4oE1RcPI0n8W/cR23CUa6vc34=";

  meta = {
    description = "Manage your DFWADs, extract and create them.";
    homepage = "https://github.com/Doom2D/dfwad";
    license = lib.licenses.unlicense;
    mainProgram = "dfw-rs";
  };
}
