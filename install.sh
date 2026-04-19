#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  ITL ControlPlane Stack — Partner Installer (Linux/macOS)
#
#  Usage:
#    ./install.sh                           # interactive wizard
#    ./install.sh --mode docker --unattended \
#      --partner MyCompany --domain platform.acmecorp.com \
#      --admin-email admin@acmecorp.com
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
MODE=""
PARTNER_NAME=""
DOMAIN=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
KUBE_CONTEXT=""
TALOS_ENDPOINT=""
UNATTENDED=false
DRY_RUN=false

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; GRAY='\033[0;37m'; NC='\033[0m'

step()  { echo -e "  ${CYAN}[→]${NC} $*"; }
ok()    { echo -e "  ${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "  ${YELLOW}[!]${NC} $*"; }
fail()  { echo -e "  ${RED}[✗]${NC} $*"; }
info()  { echo -e "      $*"; }

banner() {
  clear
  echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗"
  echo -e "  ║     ITL ControlPlane — Partner Stack Installer           ║"
  echo -e "  ║     Version 1.0  •  itlusions.com                        ║"
  echo -e "  ╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

ask() {
  local prompt="$1" default="${2:-}"
  local hint=""
  [[ -n "$default" ]] && hint=" [$default]"
  read -rp "  → ${prompt}${hint}: " answer
  echo "${answer:-$default}"
}

ask_secret() {
  local prompt="$1"
  read -rsp "  → ${prompt}: " answer
  echo ""
  echo "$answer"
}

# ── Secret generation ─────────────────────────────────────────────────────────
gen_password() {
  local len="${1:-24}"
  tr -dc 'A-Za-z0-9!@#$' < /dev/urandom | head -c "$len" || true
}

gen_token() {
  local len="${1:-32}"
  dd if=/dev/urandom bs=1 count="$len" 2>/dev/null | base64 | tr -d '\n/+=' | head -c "$(( len * 4 / 3 ))"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)           MODE="$2";          shift 2 ;;
    --partner)        PARTNER_NAME="$2";  shift 2 ;;
    --domain)         DOMAIN="$2";        shift 2 ;;
    --admin-email)    ADMIN_EMAIL="$2";   shift 2 ;;
    --admin-password) ADMIN_PASSWORD="$2";shift 2 ;;
    --kube-context)   KUBE_CONTEXT="$2";  shift 2 ;;
    --talos-endpoint) TALOS_ENDPOINT="$2";shift 2 ;;
    --unattended)     UNATTENDED=true;    shift   ;;
    --dry-run)        DRY_RUN=true;       shift   ;;
    *) fail "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Preflight ─────────────────────────────────────────────────────────────────
preflight() {
  step "Running preflight checks..."
  local ok_flag=true

  case "$MODE" in
    docker)
      if ! command -v docker &>/dev/null; then
        fail "Docker not found. Install from https://docs.docker.com/get-docker/"
        ok_flag=false
      else
        ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null) found"
      fi
      ;;
    k8s)
      command -v kubectl &>/dev/null && ok "kubectl found" || { fail "kubectl not found"; ok_flag=false; }
      command -v helm    &>/dev/null && ok "Helm $(helm version --short 2>/dev/null) found" \
                                     || { fail "Helm 3 not found"; ok_flag=false; }
      ;;
    talos)
      command -v talosctl &>/dev/null && ok "talosctl found" || install_talosctl
      command -v kubectl  &>/dev/null && ok "kubectl found"  || { fail "kubectl not found"; ok_flag=false; }
      command -v flux     &>/dev/null && ok "flux CLI found"  || warn "flux CLI not found — will install during bootstrap"
      ;;
  esac

  $ok_flag || { echo ""; fail "Fix the issues above and re-run."; exit 1; }
  echo ""
}

install_talosctl() {
  step "Installing talosctl..."
  curl -sL https://talos.dev/install | sh && ok "talosctl installed" || warn "Auto-install failed — see https://talos.dev"
}

# ── Wizard ────────────────────────────────────────────────────────────────────
wizard() {
  banner

  echo -e "  ${WHITE}This wizard installs the ITL ControlPlane platform.${NC}"
  echo -e "  ${WHITE}Answer a few questions and your stack will be ready.${NC}"
  echo ""

  if [[ -z "$MODE" ]]; then
    echo -e "  Choose deployment mode:"
    echo -e "    ${GRAY}1) docker  — Docker Compose  (single server, quick start)${NC}"
    echo -e "    ${GRAY}2) k8s     — Kubernetes/Helm (existing cluster)${NC}"
    echo -e "    ${GRAY}3) talos   — Talos bare-metal (like Azure HCI, recommended)${NC}"
    echo ""
    choice=$(ask "Mode (1/2/3)" "1")
    case "$choice" in
      1) MODE=docker ;;
      2) MODE=k8s    ;;
      3) MODE=talos  ;;
      *) MODE=docker ;;
    esac
  fi

  echo ""
  echo -e "  ${CYAN}── Partner Configuration ─────────────────────────────${NC}"

  [[ -z "$PARTNER_NAME" ]] && PARTNER_NAME=$(ask "Partner / organisation name" "MyCompany")
  [[ -z "$DOMAIN"       ]] && DOMAIN=$(ask "Platform domain (e.g. platform.acmecorp.com)" "platform.local")
  [[ -z "$ADMIN_EMAIL"  ]] && ADMIN_EMAIL=$(ask "Admin e-mail address" "admin@${DOMAIN}")

  if [[ -z "$ADMIN_PASSWORD" ]]; then
    generated=$(gen_password 20)
    echo ""
    echo -e "  ${GRAY}Leave blank to auto-generate a secure password.${NC}"
    ADMIN_PASSWORD=$(ask_secret "Admin password (leave blank = auto-generate)")
    if [[ -z "$ADMIN_PASSWORD" ]]; then
      ADMIN_PASSWORD="$generated"
      warn "Auto-generated admin password: ${ADMIN_PASSWORD}"
      warn "SAVE THIS — it will not be shown again."
    fi
  fi

  if [[ "$MODE" == "talos" && -z "$TALOS_ENDPOINT" ]]; then
    echo ""
    echo -e "  ${CYAN}── Talos / Bare-Metal Configuration ─────────────────${NC}"
    TALOS_ENDPOINT=$(ask "IP address of the first control-plane node")
  fi

  if [[ "$MODE" == "k8s" && -z "$KUBE_CONTEXT" ]]; then
    echo ""
    KUBE_CONTEXT=$(ask "kubectl context to use" "$(kubectl config current-context 2>/dev/null || echo '')")
  fi

  echo ""
}

# ── Generate secrets + .env ───────────────────────────────────────────────────
declare -A SECRETS

generate_secrets() {
  step "Generating secrets and configuration..."

  SECRETS[PARTNER_NAME]="$PARTNER_NAME"
  SECRETS[PARTNER_DOMAIN]="$DOMAIN"
  SECRETS[ADMIN_EMAIL]="$ADMIN_EMAIL"

  SECRETS[KEYCLOAK_ADMIN]="admin"
  SECRETS[KEYCLOAK_ADMIN_PASSWORD]="$ADMIN_PASSWORD"
  SECRETS[KEYCLOAK_CLIENT_SECRET]="$(gen_token 32)"
  SECRETS[TEST_REALM_NAME]="itl-platform"
  SECRETS[TEST_USER_PASSWORD]="$(gen_password 16)"
  SECRETS[SERVICE_CLIENT_ID]="itl-identity-service"

  SECRETS[POSTGRES_PASSWORD]="$(gen_password 24)"
  SECRETS[NEO4J_PASSWORD]="$(gen_password 24)"
  SECRETS[REDIS_PASSWORD]="$(gen_password 24)"
  SECRETS[RABBITMQ_PASSWORD]="$(gen_password 24)"

  SECRETS[JWT_SECRET]="$(gen_token 48)"
  SECRETS[DOCKER_SOCKET]="/var/run/docker.sock"
}

write_env() {
  local env_file="$SCRIPT_DIR/.env"
  {
    echo "# ITL ControlPlane — Generated by install.sh on $(date '+%Y-%m-%d %H:%M')"
    echo "# DO NOT COMMIT THIS FILE"
    echo ""
    for k in $(echo "${!SECRETS[@]}" | tr ' ' '\n' | sort); do
      echo "${k}=${SECRETS[$k]}"
    done
  } > "$env_file"

  mkdir -p "$SCRIPT_DIR/keycloak"
  {
    echo "KEYCLOAK_ADMIN=${SECRETS[KEYCLOAK_ADMIN]}"
    echo "KEYCLOAK_ADMIN_PASSWORD=${SECRETS[KEYCLOAK_ADMIN_PASSWORD]}"
  } > "$SCRIPT_DIR/keycloak/.env"

  ok "Configuration written to .env"
}

# ── Install modes ─────────────────────────────────────────────────────────────
install_docker() {
  step "Starting Docker Compose stack..."
  write_env

  if $DRY_RUN; then warn "DRY RUN — skipping docker compose up"; return; fi

  cd "$SCRIPT_DIR"
  docker compose pull --quiet
  docker compose up -d --build --remove-orphans

  step "Waiting for services to become healthy (up to 3 min)..."
  local deadline=$(( $(date +%s) + 180 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    unhealthy=$(docker compose ps --format json 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin) if isinstance(json.load(open('/dev/stdin')), list) else [json.load(open('/dev/stdin'))]; print(len([x for x in d if x.get('Health') not in ('healthy','',None)]))" 2>/dev/null || echo "0")
    [[ "$unhealthy" == "0" ]] && break
    sleep 5
  done
  ok "All services healthy"
}

install_k8s() {
  step "Deploying to Kubernetes (context: ${KUBE_CONTEXT})..."

  [[ -n "$KUBE_CONTEXT" ]] && kubectl config use-context "$KUBE_CONTEXT" >/dev/null

  local helm_dir="$SCRIPT_DIR/helm"
  local values_file="$helm_dir/values.partner.yaml"

  cat > "$values_file" <<EOF
partner:
  name: "${SECRETS[PARTNER_NAME]}"
  domain: "${SECRETS[PARTNER_DOMAIN]}"
  adminEmail: "${SECRETS[ADMIN_EMAIL]}"

keycloak:
  adminPassword: "${SECRETS[KEYCLOAK_ADMIN_PASSWORD]}"
  clientSecret: "${SECRETS[KEYCLOAK_CLIENT_SECRET]}"

postgresql:
  auth:
    password: "${SECRETS[POSTGRES_PASSWORD]}"

neo4j:
  auth:
    password: "${SECRETS[NEO4J_PASSWORD]}"

redis:
  auth:
    password: "${SECRETS[REDIS_PASSWORD]}"

rabbitmq:
  auth:
    password: "${SECRETS[RABBITMQ_PASSWORD]}"

global:
  jwtSecret: "${SECRETS[JWT_SECRET]}"
EOF

  if $DRY_RUN; then warn "DRY RUN — helm install skipped. Values written to $values_file"; return; fi

  helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true
  helm dependency update "$helm_dir" 2>/dev/null || true

  helm upgrade --install itl-controlplane "$helm_dir" \
    --namespace itl-platform \
    --create-namespace \
    -f "$helm_dir/values.yaml" \
    -f "$values_file" \
    --wait --timeout 10m

  ok "Helm release deployed"
}

install_talos() {
  step "Starting Talos bare-metal bootstrap..."

  local talos_dir="$SCRIPT_DIR/talos"
  [[ -d "$talos_dir" ]] || { fail "talos/ directory not found"; exit 1; }

  if $DRY_RUN; then warn "DRY RUN — talosctl bootstrap skipped"; return; fi

  local cluster_name
  cluster_name=$(echo "$PARTNER_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')-controlplane

  step "Generating Talos machine configurations..."
  talosctl gen config "$cluster_name" "https://${TALOS_ENDPOINT}:6443" \
    --config-patch "@${talos_dir}/controlplane.patch.yaml" \
    --output-dir "$talos_dir"

  step "Applying config to ${TALOS_ENDPOINT}..."
  talosctl apply-config \
    --nodes "$TALOS_ENDPOINT" \
    --file "$talos_dir/controlplane.yaml" \
    --insecure

  step "Bootstrapping etcd (this takes ~2 minutes)..."
  sleep 30
  talosctl bootstrap --nodes "$TALOS_ENDPOINT" --talosconfig "$talos_dir/talosconfig"

  step "Fetching kubeconfig..."
  talosctl kubeconfig --nodes "$TALOS_ENDPOINT" --talosconfig "$talos_dir/talosconfig" --force --merge

  ok "Kubernetes cluster ready"
  install_flux
}

install_flux() {
  step "Bootstrapping Flux GitOps (auto-deploys full ControlPlane)..."

  local flux_dir="$SCRIPT_DIR/flux"

  if ! command -v flux &>/dev/null; then
    step "Installing flux CLI..."
    curl -s https://fluxcd.io/install.sh | bash
  fi

  generate_secrets   # ensure secrets are populated
  write_env

  kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace itl-platform --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic itl-controlplane-secrets \
    --namespace itl-platform \
    --from-literal=POSTGRES_PASSWORD="${SECRETS[POSTGRES_PASSWORD]}" \
    --from-literal=NEO4J_PASSWORD="${SECRETS[NEO4J_PASSWORD]}" \
    --from-literal=KEYCLOAK_ADMIN_PASSWORD="${SECRETS[KEYCLOAK_ADMIN_PASSWORD]}" \
    --from-literal=JWT_SECRET="${SECRETS[JWT_SECRET]}" \
    --dry-run=client -o yaml | kubectl apply -f -

  if $DRY_RUN; then warn "DRY RUN — flux bootstrap skipped"; return; fi

  kubectl apply -f "$flux_dir/gotk-sync.yaml"
  kubectl apply -f "$flux_dir/kustomization.yaml"

  ok "Flux GitOps bootstrap complete — stack will auto-deploy"
}

# ── Summary ───────────────────────────────────────────────────────────────────
show_summary() {
  echo ""
  echo -e "${GREEN}  ╔══════════════════════════════════════════════════════════╗"
  echo -e "  ║   ITL ControlPlane — Installation Complete               ║"
  echo -e "  ╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${WHITE}Access your platform:${NC}"
  case "$MODE" in
    docker)
      info "Portal       http://localhost:9052"
      info "Dashboard    http://localhost:9051"
      info "API Gateway  http://localhost:9050"
      info "Keycloak     http://localhost:8080"
      info "Neo4j        http://localhost:7474"
      info "DB Manager   http://localhost:8978"
      ;;
    k8s|talos)
      info "Portal       https://${DOMAIN}"
      info "Dashboard    https://dashboard.${DOMAIN}"
      info "API Gateway  https://api.${DOMAIN}"
      info "Keycloak     https://iam.${DOMAIN}"
      ;;
  esac
  echo ""
  echo -e "  ${WHITE}Admin credentials:${NC}"
  info "User      ${ADMIN_EMAIL}"
  info "Password  ${ADMIN_PASSWORD}"
  echo ""
  echo -e "  ${GRAY}Configuration saved to .env (do not commit this file)${NC}"
  echo -e "  ${GRAY}Documentation: docs/PARTNER_INSTALL.md${NC}"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
if ! $UNATTENDED; then
  wizard
else
  banner
  [[ -z "$MODE" ]]         && MODE=docker
  [[ -z "$PARTNER_NAME" ]] && { fail "--partner is required for unattended install"; exit 1; }
  [[ -z "$DOMAIN" ]]       && { fail "--domain is required for unattended install";  exit 1; }
  [[ -z "$ADMIN_EMAIL" ]]  && { fail "--admin-email is required for unattended install"; exit 1; }
  [[ -z "$ADMIN_PASSWORD" ]] && ADMIN_PASSWORD=$(gen_password 24)
fi

preflight
generate_secrets

case "$MODE" in
  docker) install_docker ;;
  k8s)    write_env; install_k8s ;;
  talos)  install_talos ;;
esac

show_summary
