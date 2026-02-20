#!/bin/bash
set -e



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

echo "================================================="
echo " Actyro On-Prem MongoDB Installer (k3s VM) "
echo "================================================="
echo ""

# -------------------------------------------------
# FIXED CONFIGURATION (Customer does NOT change)
# -------------------------------------------------
NAMESPACE="mongodb"

# MongoDB credentials
ROOT_USER="root"
ROOT_PASS="rootPassword"

APP_USER="onprem"
APP_PASS="onprem"

# Databases
AUTH_DB="onprem_auth"
DB1="master_auth"
DB2="testclient"

# -------------------------------------------------
# Pre-checks
# -------------------------------------------------
if ! command -v kubectl &>/dev/null; then
  echo "❌ kubectl not found. Please install k3s first."
  exit 1
fi

if ! kubectl get nodes &>/dev/null; then
  echo "❌ Kubernetes cluster not reachable. Is k3s running?"
  exit 1
fi

# -------------------------------------------------
# Install Helm if missing
# -------------------------------------------------
if ! command -v helm &>/dev/null; then
  echo "📦 Helm not found. Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# -------------------------------------------------
# Namespace
# -------------------------------------------------
kubectl create namespace ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

# -------------------------------------------------
# Helm repo
# -------------------------------------------------
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
helm repo update >/dev/null

# -------------------------------------------------
# MongoDB values.yaml
# NOTE:
# - Only AUTH_DB is created by Helm
# - Other DBs are created manually later
# -------------------------------------------------
cat <<EOF > mongodb-values.yaml
architecture: standalone
useStatefulSet: true

auth:
  enabled: true
  rootUser: ${ROOT_USER}
  rootPassword: ${ROOT_PASS}

  usernames:
    - ${APP_USER}
  passwords:
    - ${APP_PASS}
  databases:
    - ${AUTH_DB}

persistence:
  enabled: true
  storageClass: local-path
  size: 10Gi

service:
  type: ClusterIP
EOF

# -------------------------------------------------
# Fresh install (idempotent)
# -------------------------------------------------
echo "🚀 Installing MongoDB..."

helm uninstall mongodb -n ${NAMESPACE} >/dev/null 2>&1 || true
kubectl delete pvc -n ${NAMESPACE} --all >/dev/null 2>&1 || true

helm install mongodb bitnami/mongodb \
  -n ${NAMESPACE} \
  -f mongodb-values.yaml

# -------------------------------------------------
# Wait for MongoDB StatefulSet
# -------------------------------------------------
echo "⏳ Waiting for MongoDB to be ready..."
kubectl rollout status statefulset mongodb -n ${NAMESPACE}

# -------------------------------------------------
# Create application databases + assign roles
# -------------------------------------------------
echo "🗄️ Creating databases and assigning roles..."

kubectl exec -n ${NAMESPACE} mongodb-0 -- mongosh \
  -u ${ROOT_USER} \
  -p ${ROOT_PASS} \
  --authenticationDatabase admin <<EOF

// Create master_auth DB
use ${DB1}
db.init.insertOne({ createdAt: new Date() })

// Create testclient DB
use ${DB2}
db.init.insertOne({ createdAt: new Date() })

// Grant access to app user
use ${AUTH_DB}
db.grantRolesToUser("${APP_USER}", [
  { role: "readWrite", db: "${DB1}" },
  { role: "readWrite", db: "${DB2}" }
])
EOF

# -------------------------------------------------
# CoreDNS loop fix (safe & idempotent)
# -------------------------------------------------
echo "🛠️ Fixing cluster DNS (CoreDNS)..."

kubectl patch configmap coredns -n kube-system --type merge -p '{
  "data": {
    "Corefile": ".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    forward . 8.8.8.8 1.1.1.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}"
  }
}'

kubectl rollout restart deployment coredns -n kube-system

# -------------------------------------------------
# Final output for customer validation
# -------------------------------------------------
echo ""
echo "================================================="
echo " ✅ MongoDB Installed Successfully"
echo "================================================="
echo ""
echo "Authentication Database : ${AUTH_DB}"
echo "Application Databases   : ${DB1}, ${DB2}"
echo ""
echo "MongoDB Username        : ${APP_USER}"
echo "MongoDB Password        : ${APP_PASS}"
echo ""
echo "Connection URLs:"
echo ""
echo "MASTER_AUTH:"
echo "mongodb://${APP_USER}:${APP_PASS}@mongodb.mongodb.svc.cluster.local:27017/${DB1}?authSource=${AUTH_DB}"
echo ""
echo "TESTCLIENT:"
echo "mongodb://${APP_USER}:${APP_PASS}@mongodb.mongodb.svc.cluster.local:27017/${DB2}?authSource=${AUTH_DB}"

echo ""
echo "============================================="
echo "MongoDB is running as a StatefulSet on k3s VM"
echo "============================================="

log "StatefulSet status: kubectl get sts -n ${NAMESPACE}"

log "MongoDB pod status: kubectl get pods -n ${NAMESPACE}"

log "Persistent Volume Claims: kubectl get pvc -n ${NAMESPACE}"

log "MongoDB service: kubectl get svc -n ${NAMESPACE}"

log "MongoDB DNS: mongodb.${NAMESPACE}.svc.cluster.local"

log "Node status: kubectl get nodes"


log "Disk usage on node (important for stability): df -h /"

echo "============================================="
echo "Installation completed successfully"
echo "============================================="


echo "---------------------------------------------"