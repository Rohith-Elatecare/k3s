#!/bin/bash

# ===== GLOBAL CONFIG =====
DEFAULT_NAMESPACE="run-tests"
OUTPUT_DIR="generated-secrets"
# =========================

# Service → fixed secret mapping
declare -A SERVICE_SECRETS=(
  ["auth-service"]="auth-service-secret-test"
  ["run-tests-service"]="run-tests-service-secret-test"
  ["projects-service"]="projects-service-secret-test"
)

# Enforced order
ORDERED_SERVICES=(
  "auth-service"
  "run-tests-service"
  "projects-service"
)

# ─────────────────────────────────────────────
# Ask for namespace (ONCE)
# ─────────────────────────────────────────────
read -p "Enter Kubernetes namespace [default: $DEFAULT_NAMESPACE]: " NAMESPACE
NAMESPACE=${NAMESPACE:-$DEFAULT_NAMESPACE}

# Validate namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo ""
  echo "❌ ERROR: Kubernetes namespace '$NAMESPACE' does not exist."
  echo "👉 Please create it first:"
  echo "   kubectl create namespace $NAMESPACE"
  echo ""
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ─────────────────────────────────────────────
# Ask which secrets to update
# ─────────────────────────────────────────────
echo ""
echo "Which secrets do you want to update?"
echo "1) auth-service"
echo "2) run-tests-service"
echo "3) projects-service"
echo "4) all"
echo ""

read -p "Enter choice (e.g. 1 or 1,3 or 4): " CHOICE

SELECTED_SERVICES=()

if [[ "$CHOICE" == "4" ]]; then
  SELECTED_SERVICES=("${ORDERED_SERVICES[@]}")
else
  IFS=',' read -ra PICKS <<< "$CHOICE"
  for PICK in "${PICKS[@]}"; do
    case "$PICK" in
      1) SELECTED_SERVICES+=("auth-service") ;;
      2) SELECTED_SERVICES+=("run-tests-service") ;;
      3) SELECTED_SERVICES+=("projects-service") ;;
      *)
        echo "❌ Invalid selection: $PICK"
        exit 1
        ;;
    esac
  done
fi

echo ""
echo "📦 Namespace: $NAMESPACE"
echo "📁 Output directory: $OUTPUT_DIR"
echo "🔁 Services to update: ${SELECTED_SERVICES[*]}"
echo ""

# ─────────────────────────────────────────────
# Process and APPLY secrets
# ─────────────────────────────────────────────
for SERVICE in "${ORDERED_SERVICES[@]}"; do
  [[ " ${SELECTED_SERVICES[*]} " != *" $SERVICE "* ]] && continue

  SECRET_NAME="${SERVICE_SECRETS[$SERVICE]}"
  ENV_FILE="${SERVICE}.env"
  OUTPUT_FILE="${OUTPUT_DIR}/${SECRET_NAME}.yaml"

  echo "────────────────────────────────────────"
  echo "➡️  Processing $SERVICE"
  echo "🔐 Secret name: $SECRET_NAME"
  echo "────────────────────────────────────────"

  if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Missing $ENV_FILE — aborting"
    exit 1
  fi

  # Generate YAML
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

    # Strip surrounding quotes
    value="${value%\"}"
    value="${value#\"}"

    # Escape remaining quotes
    value=$(echo "$value" | sed 's/"/\\"/g')

    echo "  $key: \"$value\"" >> "$OUTPUT_FILE"
  done < "$ENV_FILE"

  echo "📦 Applying secret to Kubernetes..."
  kubectl apply -f "$OUTPUT_FILE" || {
    echo "❌ Failed to apply $SECRET_NAME"
    exit 1
  }

  echo "✅ Secret '$SECRET_NAME' applied successfully"
done

echo ""
echo "🎉 All selected secrets updated successfully in namespace '$NAMESPACE'"
echo "🚀 No further action required"


# mkdir -p secrets && touch secrets/auth-service.env secrets/run-tests-service.env secrets/projects-service.env secrets/portal.env secrets/env-to-secrets.sh