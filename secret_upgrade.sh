#!/bin/bash
set -e

# =================================================
# Secret Upgrade Script (curl | bash safe)
# =================================================

OUTPUT_DIR="generated-secrets"

# Fixed service → secret mapping (DO NOT CHANGE)
declare -A SERVICE_SECRETS=(
  ["auth-service"]="auth-service-secret-test"
  ["run-tests-service"]="run-tests-service-secret-test"
  ["projects-service"]="projects-service-secret-test"
)

# Enforced processing order
ORDERED_SERVICES=(
  "auth-service"
  "run-tests-service"
  "projects-service"
)

echo "🔐 Starting Secret Upgrade Script"
echo ""

# =================================================
# Namespace validation
# =================================================
if [ -z "$NAMESPACE" ]; then
  echo "❌ ERROR: NAMESPACE is not set."
  echo "👉 Usage:"
  echo "   curl -fsSL <url> | NAMESPACE=<ns> SERVICES=all bash"
  exit 1
fi

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo ""
  echo "❌ ERROR: Kubernetes namespace '$NAMESPACE' does not exist."
  echo "👉 Please create it first:"
  echo "   kubectl create namespace $NAMESPACE"
  exit 1
fi

echo "📦 Namespace: $NAMESPACE"

# =================================================
# Service selection
# =================================================
if [ -z "$SERVICES" ]; then
  echo ""
  echo "❌ ERROR: SERVICES is not set."
  echo "👉 Examples:"
  echo "   SERVICES=all"
  echo "   SERVICES=auth-service"
  echo "   SERVICES=auth-service,projects-service"
  exit 1
fi

if [[ "$SERVICES" == "all" ]]; then
  SELECTED_SERVICES=("${ORDERED_SERVICES[@]}")
else
  IFS=',' read -ra SELECTED_SERVICES <<< "$SERVICES"
fi

# =================================================
# Service validation
# =================================================
INVALID_SERVICES=()

for SVC in "${SELECTED_SERVICES[@]}"; do
  if [[ ! " ${ORDERED_SERVICES[*]} " =~ " $SVC " ]]; then
    INVALID_SERVICES+=("$SVC")
  fi
done

if [ ${#INVALID_SERVICES[@]} -ne 0 ]; then
  echo ""
  echo "❌ ERROR: Invalid service name(s): ${INVALID_SERVICES[*]}"
  echo "👉 Allowed services:"
  for ALLOWED in "${ORDERED_SERVICES[@]}"; do
    echo "   - $ALLOWED"
  done
  exit 1
fi

echo "🔁 Services to update: ${SELECTED_SERVICES[*]}"
echo ""

mkdir -p "$OUTPUT_DIR"

# =================================================
# Process & apply secrets
# =================================================
for SERVICE in "${ORDERED_SERVICES[@]}"; do
  [[ " ${SELECTED_SERVICES[*]} " != *" $SERVICE "* ]] && continue

  SECRET_NAME="${SERVICE_SECRETS[$SERVICE]}"
  ENV_FILE="${SERVICE}.env"
  OUTPUT_FILE="${OUTPUT_DIR}/${SECRET_NAME}.yaml"

  echo "────────────────────────────────────────"
  echo "➡️  Processing $SERVICE"
  echo "🔐 Secret name: $SECRET_NAME"

  if [ ! -f "$ENV_FILE" ]; then
    echo "❌ ERROR: Missing $ENV_FILE"
    exit 1
  fi

  # Generate Secret YAML
  cat > "$OUTPUT_FILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
type: Opaque
stringData:
EOF

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue

    # Remove surrounding quotes if present
    value="${value%\"}"
    value="${value#\"}"

    # Escape internal quotes
    value=$(echo "$value" | sed 's/"/\\"/g')

    echo "  $key: \"$value\"" >> "$OUTPUT_FILE"
  done < "$ENV_FILE"

  echo "📦 Applying secret to Kubernetes..."
  kubectl apply -f "$OUTPUT_FILE"

  echo "✅ Secret '$SECRET_NAME' applied successfully"
done

echo ""
echo "🎉 Secret upgrade completed successfully"
echo "🚀 No further action required"


# mkdir -p secrets && touch secrets/auth-service.env secrets/run-tests-service.env secrets/projects-service.env secrets/portal.env secrets/env-to-secrets.sh