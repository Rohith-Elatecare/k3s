#!/bin/bash
set -euo pipefail

#####################################
# Configuration
#####################################
REPO="Rohith-Elatecare/k3s"
RELEASE_NAME="actyro"
NAMESPACE="actyro"

SERVICES=(
  auth-service
  projects-service
  run-tests-service
  portal
)

IMAGES_DIR="/opt/releases/actyro_images"

ROOT_DIR="$(pwd)"
HELM_ROOT="$ROOT_DIR/actyro/actyro"
VALUES_FILE="$HELM_ROOT/values.yaml"

#####################################
# Helpers
#####################################
log() {
  echo -e "\e[32m[INFO]\e[0m $1"
}

warn() {
  echo -e "\e[33m[WARN]\e[0m $1"
}

error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
  exit 1
}

#####################################
# Pre-checks
#####################################

command -v curl >/dev/null 2>&1 || error "curl not installed"
command -v helm >/dev/null 2>&1 || error "helm not installed"
command -v kubectl >/dev/null 2>&1 || error "kubectl not installed"
command -v k3s >/dev/null 2>&1 || error "k3s not installed"

[ -d "$HELM_ROOT" ] || error "Helm chart not found: $HELM_ROOT"
[ -f "$VALUES_FILE" ] || error "values.yaml not found: $VALUES_FILE"

# Disk space check (warn if >85%)
USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$USAGE" -gt 85 ]; then
  warn "Root disk usage is ${USAGE}% — consider freeing space before upgrade"
fi

mkdir -p "$IMAGES_DIR"

#####################################
# Download images
#####################################
log "Downloading latest Actyro images from public GitHub release..."

for svc in "${SERVICES[@]}"; do
  TAR_NAME="${svc}.tar"
  TAR_PATH="$IMAGES_DIR/$TAR_NAME"

  log "Downloading $TAR_NAME..."

  curl -fL \
    -o "$TAR_PATH" \
    "https://github.com/$REPO/releases/latest/download/$TAR_NAME" \
    || error "Failed to download $TAR_NAME"

  log "Saved to $TAR_PATH"
done

#####################################
# Import images into k3s
#####################################
log "Importing images into k3s containerd..."

for img in "$IMAGES_DIR"/*.tar; do
  log "Importing $(basename "$img")"
  sudo k3s ctr images import "$img" || error "Failed importing $img"
done

log "All images imported successfully"

#####################################
# Helm upgrade
#####################################
log "Deploying upgrade via Helm..."

helm upgrade --install "$RELEASE_NAME" "$HELM_ROOT" \
  -f "$VALUES_FILE" \
  -n "$NAMESPACE" \
  --create-namespace \
  || error "Helm upgrade failed"

#####################################
# Restart deployments
#####################################
log "Restarting deployments..."

for svc in "${SERVICES[@]}"; do
  kubectl rollout restart deployment "actyro-$svc" -n "$NAMESPACE" || warn "Restart failed for $svc"
done

#####################################
# Status check
#####################################
log "Current pod status:"
kubectl get pods -n "$NAMESPACE"

log "✅ Actyro upgrade completed successfully"
