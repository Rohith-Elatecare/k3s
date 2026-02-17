#!/bin/bash
set -e

#####################################
# Configuration
#####################################
REPO="Rohith-Elatecare/k3s"
RELEASE_NAME="actyro"
NAMESPACE="actyro"

# Images to download (must exist as release assets)
SERVICES=(
  auth-service
  projects-service
  run-tests-service
  portal
)

# Persistent image location
IMAGES_DIR="/opt/releases/actyro_images"

# Helm root (relative to where script is run)
ROOT_DIR="$(pwd)"
HELM_ROOT="$ROOT_DIR/actyro/actyro"
VALUES_FILE="$HELM_ROOT/values.yaml"

#####################################
# Helpers
#####################################
log() {
  echo "[INFO] $1"
}

error() {
  echo "[ERROR] $1"
  exit 1
}

#####################################
# Pre-checks
#####################################
[ -z "$GITHUB_TOKEN" ] && error "GITHUB_TOKEN not set"

command -v curl >/dev/null 2>&1 || error "curl not installed"
command -v helm >/dev/null 2>&1 || error "helm not installed"
command -v kubectl >/dev/null 2>&1 || error "kubectl not installed"
command -v k3s >/dev/null 2>&1 || error "k3s not installed"

[ -d "$HELM_ROOT" ] || error "Helm root chart not found: $HELM_ROOT"
[ -f "$VALUES_FILE" ] || error "values.yaml not found: $VALUES_FILE"

mkdir -p "$IMAGES_DIR"

#####################################
# Download latest images
#####################################
log "Downloading latest Actyro images from private GitHub release..."

for svc in "${SERVICES[@]}"; do
  TAR_NAME="${svc}.tar"
  TAR_PATH="$IMAGES_DIR/$TAR_NAME"

  log "Downloading $TAR_NAME"
  curl -L \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -o "$TAR_PATH" \
    "https://github.com/$REPO/releases/latest/download/$TAR_NAME"

  log "Downloaded $(ls -lh "$TAR_PATH")"
done

#####################################
# Optional checksum verification
#####################################
# if curl -s -f \
#   -H "Authorization: Bearer $GITHUB_TOKEN" \
#   -o "$IMAGES_DIR/checksums.sha256" \
#   "https://github.com/$REPO/releases/latest/download/checksums.sha256"; then

#   log "Verifying checksums..."
#   (cd "$IMAGES_DIR" && sha256sum -c checksums.sha256)

# else
#   log "No checksums.sha256 found – skipping verification"
# fi

#####################################
# Import images into k3s
#####################################
log "Importing images into k3s containerd..."

for img in "$IMAGES_DIR"/*.tar; do
  log "Importing $(basename "$img")"
  sudo k3s ctr images import "$img"
done

log "All images imported successfully"

#####################################
# Helm upgrade (umbrella chart)
#####################################
log "Upgrading Actyro platform using Helm..."

helm upgrade --install "$RELEASE_NAME" "$HELM_ROOT" \
  -f "$VALUES_FILE" \
  -n "$NAMESPACE" \
  --create-namespace

#####################################
# Post-upgrade checks
#####################################
log "Restarting deployments..."

for svc in "${SERVICES[@]}"; do
  kubectl rollout restart deployment "actyro-$svc" -n "$NAMESPACE" || true
done

log "Current pod status:"
kubectl get pods -n "$NAMESPACE"

log "✅ Actyro upgrade completed successfully"