#!/bin/bash
set -euo pipefail
D2DF_LAST_COMMIT_DATE="2025-03-04 22:30:32 +0300"
EDITOR_LAST_COMMIT_DATE="2025-03-05 00:05:50 +1000"
RES_LAST_COMMIT_DATE="2025-02-23 14:52:10 +1000"
LAST_COMMIT=$(git rev-parse HEAD)
CMD=$(
cat <<EOF
(builtins.getFlake (builtins.toString ./.)).outputs.legacyPackages.x86_64-linux.$BUNDLE_NAME.override
(prev: {
  executables = prev.executables.override {gameDate = "$D2DF_LAST_COMMIT_DATE"; editorDate = "$EDITOR_LAST_COMMIT_DATE"; withDates = true;};
  assets = prev.assets.override {editorDate = "$EDITOR_LAST_COMMIT_DATE"; assetsDate = "$RES_LAST_COMMIT_DATE"; withDates = true;};
})
EOF
)
nix build \
    --show-trace --verbose --print-out-paths --print-build-logs \
    --impure --expr "$CMD"
