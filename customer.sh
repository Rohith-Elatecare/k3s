#!/bin/bash
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN not set}"

REPO="Networkissue/k3s"
VERSION="v1.0.0"
ASSET="upgrade.sh"

rm -f "$ASSET"

curl --fail --location \
  --header "Authorization: Bearer $GITHUB_TOKEN" \
  --header "Accept: application/octet-stream" \
  --output "$ASSET" \
  "https://github.com/$REPO/releases/download/$VERSION/$ASSET"

chmod +x "$ASSET"
exec ./"$ASSET"
