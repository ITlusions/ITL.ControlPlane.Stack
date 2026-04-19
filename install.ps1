#!/usr/bin/env pwsh
# ════════════════════════════════════════════════════════════════════════════
#  ITL ControlPlane Stack — Partner Installer
#  Installs the full ITL ControlPlane platform in three modes:
#
#    docker   — Docker Compose on any Linux/Windows server (default)
#    k8s      — Helm chart on an existing Kubernetes cluster
#    talos    — Full bare-metal Talos Linux + Kubernetes + GitOps bootstrap
#
#  Usage:
#    ./install.ps1                           # interactive wizard
#    ./install.ps1 -Mode docker -Unattended  # silent docker install
#    ./install.ps1 -Mode k8s    -Unattended  # silent helm install
#    ./install.ps1 -Mode talos  -Unattended  # silent talos bootstrap
# ════════════════════════════════════════════════════════════════════════════

param(
    [ValidateSet("docker","k8s","talos")]
    [string]$Mode = "",

    [string]$PartnerName    = "",
    [string]$Domain         = "",
    [string]$AdminEmail     = "",
    [string]$AdminPassword  = "",
    [string]$KubeContext    = "",
    [string]$TalosEndpoint  = "",

    [switch]$Unattended,
    [switch]$SkipPreflight,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ── Colours ─────────────────────────────────────────────────────────────────
function Write-Banner {
    Clear-Host
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║     ITL ControlPlane — Partner Stack Installer           ║" -ForegroundColor Cyan
    Write-Host "  ║     Version 1.0  •  itlusions.com                        ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step([string]$msg)    { Write-Host "  [→] $msg" -ForegroundColor Cyan   }
function Write-OK([string]$msg)      { Write-Host "  [✓] $msg" -ForegroundColor Green  }
function Write-Warn([string]$msg)    { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg)    { Write-Host "  [✗] $msg" -ForegroundColor Red    }
function Write-Info([string]$msg)    { Write-Host "      $msg" }

function Ask([string]$prompt, [string]$default = "") {
    $hint = if ($default) { " [$default]" } else { "" }
    $answer = Read-Host "  → $prompt$hint"
    if ([string]::IsNullOrWhiteSpace($answer) -and $default) { return $default }
    return $answer
}

function AskSecret([string]$prompt) {
    $ss = Read-Host "  → $prompt" -AsSecureString
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
}

function New-SecurePassword([int]$length = 24) {
    $chars  = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$"
    $result = ""
    $rng    = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes  = New-Object byte[] $length
    $rng.GetBytes($bytes)
    foreach ($b in $bytes) { $result += $chars[$b % $chars.Length] }
    return $result
}

function New-Token([int]$length = 32) {
    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $length
    $rng.GetBytes($bytes)
    return [Convert]::ToBase64String($bytes)
}

# ── Preflight checks ─────────────────────────────────────────────────────────
function Test-Command([string]$cmd) {
    return $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Invoke-Preflight([string]$mode) {
    Write-Step "Running preflight checks..."
    $ok = $true

    switch ($mode) {
        "docker" {
            if (-not (Test-Command "docker")) {
                Write-Fail "Docker is not installed. Install from https://docs.docker.com/get-docker/"
                $ok = $false
            } else {
                $v = docker version --format '{{.Server.Version}}' 2>$null
                Write-OK "Docker $v found"
            }
            if (-not (Test-Command "docker")) {
                Write-Fail "Docker Compose is not available"
                $ok = $false
            }
        }
        "k8s" {
            if (-not (Test-Command "kubectl")) {
                Write-Fail "kubectl is not installed. Install from https://kubernetes.io/docs/tasks/tools/"
                $ok = $false
            } else { Write-OK "kubectl found" }
            if (-not (Test-Command "helm")) {
                Write-Fail "Helm 3 is not installed. Install from https://helm.sh/docs/intro/install/"
                $ok = $false
            } else {
                $hv = helm version --short 2>$null
                Write-OK "Helm $hv found"
            }
        }
        "talos" {
            if (-not (Test-Command "talosctl")) {
                Write-Warn "talosctl not found — will attempt auto-install"
                Install-Talosctl
            } else { Write-OK "talosctl found" }
            if (-not (Test-Command "kubectl")) {
                Write-Fail "kubectl is not installed"
                $ok = $false
            } else { Write-OK "kubectl found" }
            if (-not (Test-Command "flux")) {
                Write-Warn "flux CLI not found — will install via bootstrap"
            } else { Write-OK "flux CLI found" }
        }
    }

    if (-not $ok) {
        Write-Host ""
        Write-Fail "Preflight failed. Fix the issues above and re-run."
        exit 1
    }
    Write-Host ""
}

function Install-Talosctl {
    Write-Step "Installing talosctl..."
    try {
        if ($IsWindows) {
            $rel = Invoke-RestMethod "https://api.github.com/repos/siderolabs/talos/releases/latest"
            $url = ($rel.assets | Where-Object { $_.name -eq "talosctl-windows-amd64.exe" }).browser_download_url
            $dest = "$env:LOCALAPPDATA\Microsoft\WindowsApps\talosctl.exe"
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        } else {
            Invoke-Expression (Invoke-WebRequest -Uri "https://talos.dev/install" -UseBasicParsing).Content
        }
        Write-OK "talosctl installed"
    } catch {
        Write-Warn "Auto-install failed. Get talosctl from https://github.com/siderolabs/talos/releases"
    }
}

# ── Wizard ───────────────────────────────────────────────────────────────────
function Invoke-Wizard {
    Write-Banner

    Write-Host "  This wizard installs the ITL ControlPlane platform." -ForegroundColor White
    Write-Host "  Answer a few questions and your stack will be ready." -ForegroundColor White
    Write-Host ""

    # Deployment mode
    if (-not $script:Mode) {
        Write-Host "  Choose deployment mode:" -ForegroundColor White
        Write-Host "    1) docker  — Docker Compose  (single server, quick start)" -ForegroundColor Gray
        Write-Host "    2) k8s     — Kubernetes/Helm (existing cluster)"            -ForegroundColor Gray
        Write-Host "    3) talos   — Talos bare-metal (like Azure HCI, recommended)" -ForegroundColor Gray
        Write-Host ""
        $choice = Ask "Mode (1/2/3)" "1"
        $script:Mode = @{"1"="docker";"2"="k8s";"3"="talos"}[$choice]
        if (-not $script:Mode) { $script:Mode = "docker" }
    }

    Write-Host ""
    Write-Host "  ── Partner Configuration ─────────────────────────────" -ForegroundColor DarkCyan

    if (-not $script:PartnerName) {
        $script:PartnerName = Ask "Partner / organisation name" "MyCompany"
    }
    if (-not $script:Domain) {
        $script:Domain = Ask "Platform domain (e.g. platform.acmecorp.com)" "platform.local"
    }
    if (-not $script:AdminEmail) {
        $script:AdminEmail = Ask "Admin e-mail address" "admin@$($script:Domain)"
    }
    if (-not $script:AdminPassword) {
        $generated = New-SecurePassword 20
        Write-Host ""
        Write-Host "  Leave blank to auto-generate a secure password." -ForegroundColor DarkGray
        $input = Ask "Admin password (leave blank = auto-generate)"
        $script:AdminPassword = if ($input) { $input } else { $generated }
        if (-not $input) {
            Write-Host ""
            Write-Warn "  Auto-generated admin password: $($script:AdminPassword)"
            Write-Warn "  SAVE THIS — it will not be shown again."
        }
    }

    if ($script:Mode -eq "talos" -and -not $script:TalosEndpoint) {
        Write-Host ""
        Write-Host "  ── Talos / Bare-Metal Configuration ─────────────────" -ForegroundColor DarkCyan
        $script:TalosEndpoint = Ask "IP address of the first control-plane node"
    }

    if ($script:Mode -eq "k8s" -and -not $script:KubeContext) {
        Write-Host ""
        $contexts = kubectl config get-contexts -o name 2>$null
        if ($contexts) {
            Write-Host "  Available kubectl contexts:" -ForegroundColor DarkGray
            $contexts | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
        }
        $script:KubeContext = Ask "kubectl context to use" (kubectl config current-context 2>$null)
    }

    Write-Host ""
}

# ── Secret generation & .env ─────────────────────────────────────────────────
function New-PartnerSecrets {
    Write-Step "Generating secrets and configuration..."

    $secrets = @{
        PARTNER_NAME          = $script:PartnerName
        PARTNER_DOMAIN        = $script:Domain
        ADMIN_EMAIL           = $script:AdminEmail

        # Keycloak
        KEYCLOAK_ADMIN        = "admin"
        KEYCLOAK_ADMIN_PASSWORD = $script:AdminPassword
        KEYCLOAK_CLIENT_SECRET  = New-Token 32
        TEST_REALM_NAME         = "itl-platform"
        TEST_USER_PASSWORD      = New-SecurePassword 16
        SERVICE_CLIENT_ID       = "itl-identity-service"

        # Databases
        POSTGRES_PASSWORD       = New-SecurePassword 24
        NEO4J_PASSWORD          = New-SecurePassword 24
        REDIS_PASSWORD          = New-SecurePassword 24
        RABBITMQ_PASSWORD       = New-SecurePassword 24

        # JWT / internal signing
        JWT_SECRET              = New-Token 48

        # Docker socket
        DOCKER_SOCKET           = if ($IsWindows) { "//var/run/docker.sock" } else { "/var/run/docker.sock" }
    }

    return $secrets
}

function Write-EnvFile([hashtable]$secrets, [string]$path) {
    $lines = @(
        "# ITL ControlPlane — Generated by install.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "# DO NOT COMMIT THIS FILE",
        ""
    )
    foreach ($k in ($secrets.Keys | Sort-Object)) {
        $lines += "$k=$($secrets[$k])"
    }
    $lines | Out-File -FilePath $path -Encoding utf8
    # Keycloak sub-env
    $kcLines = @(
        "KEYCLOAK_ADMIN=$($secrets.KEYCLOAK_ADMIN)",
        "KEYCLOAK_ADMIN_PASSWORD=$($secrets.KEYCLOAK_ADMIN_PASSWORD)"
    )
    $kcLines | Out-File -FilePath (Join-Path (Split-Path $path) "keycloak/.env") -Encoding utf8
    Write-OK "Configuration written to $(Split-Path $path -Leaf)"
}

# ── Docker Compose install ────────────────────────────────────────────────────
function Install-Docker([hashtable]$secrets) {
    Write-Step "Starting Docker Compose stack..."

    $envPath = Join-Path $PSScriptRoot ".env"
    Write-EnvFile $secrets $envPath

    if ($DryRun) {
        Write-Warn "DRY RUN — skipping docker compose up"
        return
    }

    Push-Location $PSScriptRoot
    try {
        docker compose pull --quiet
        docker compose up -d --build --remove-orphans
        Write-OK "Stack started"
    } finally {
        Pop-Location
    }

    # Wait for health
    Write-Step "Waiting for services to become healthy (up to 3 min)..."
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        $unhealthy = docker compose ps --format json 2>$null |
            ConvertFrom-Json |
            Where-Object { $_.Health -and $_.Health -notin @("healthy","") }
        if (-not $unhealthy) { break }
        Start-Sleep 5
    }
    Write-OK "All services healthy"
}

# ── Kubernetes / Helm install ─────────────────────────────────────────────────
function Install-K8s([hashtable]$secrets) {
    Write-Step "Deploying to Kubernetes (context: $($script:KubeContext))..."

    if ($script:KubeContext) {
        kubectl config use-context $script:KubeContext | Out-Null
    }

    $valuesFile = Join-Path $PSScriptRoot "helm/values.partner.yaml"
    $helmDir    = Join-Path $PSScriptRoot "helm"

    # Write partner values override
    $valuesContent = @"
partner:
  name: "$($secrets.PARTNER_NAME)"
  domain: "$($secrets.PARTNER_DOMAIN)"
  adminEmail: "$($secrets.ADMIN_EMAIL)"

keycloak:
  adminPassword: "$($secrets.KEYCLOAK_ADMIN_PASSWORD)"
  clientSecret: "$($secrets.KEYCLOAK_CLIENT_SECRET)"

postgresql:
  auth:
    password: "$($secrets.POSTGRES_PASSWORD)"

neo4j:
  auth:
    password: "$($secrets.NEO4J_PASSWORD)"

redis:
  auth:
    password: "$($secrets.REDIS_PASSWORD)"

rabbitmq:
  auth:
    password: "$($secrets.RABBITMQ_PASSWORD)"

global:
  jwtSecret: "$($secrets.JWT_SECRET)"
"@
    $valuesContent | Out-File -FilePath $valuesFile -Encoding utf8

    if ($DryRun) {
        Write-Warn "DRY RUN — helm install skipped. Values written to $valuesFile"
        return
    }

    # Add Helm dependencies (Bitnami)
    helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>$null
    helm dependency update $helmDir 2>$null

    helm upgrade --install itl-controlplane $helmDir `
        --namespace itl-platform `
        --create-namespace `
        -f (Join-Path $helmDir "values.yaml") `
        -f $valuesFile `
        --wait --timeout 10m

    Write-OK "Helm release deployed"
}

# ── Talos bootstrap ───────────────────────────────────────────────────────────
function Install-Talos([hashtable]$secrets) {
    Write-Step "Starting Talos bare-metal bootstrap..."

    $talosDir = Join-Path $PSScriptRoot "talos"
    if (-not (Test-Path $talosDir)) {
        Write-Fail "talos/ directory not found in Stack repo"
        exit 1
    }

    if ($DryRun) {
        Write-Warn "DRY RUN — talosctl bootstrap skipped"
        return
    }

    # Generate machine configs
    Write-Step "Generating Talos machine configurations..."
    $clusterName = ($script:PartnerName -replace '\s','-').ToLower() + "-controlplane"
    $endpoint    = "https://$($script:TalosEndpoint):6443"

    talosctl gen config $clusterName $endpoint `
        --config-patch "@$talosDir/controlplane.patch.yaml" `
        --output-dir $talosDir

    # Apply to first control plane node
    Write-Step "Applying config to $($script:TalosEndpoint)..."
    talosctl apply-config `
        --nodes $script:TalosEndpoint `
        --file "$talosDir/controlplane.yaml" `
        --insecure

    # Bootstrap etcd
    Write-Step "Bootstrapping etcd (this takes ~2 minutes)..."
    Start-Sleep 30
    talosctl bootstrap --nodes $script:TalosEndpoint --talosconfig "$talosDir/talosconfig"

    # Get kubeconfig
    Write-Step "Fetching kubeconfig..."
    talosctl kubeconfig --nodes $script:TalosEndpoint --talosconfig "$talosDir/talosconfig" `
        --force --merge

    Write-OK "Kubernetes cluster ready"

    # Bootstrap Flux GitOps → deploys the full ControlPlane Stack
    Install-Flux $secrets
}

function Install-Flux([hashtable]$secrets) {
    Write-Step "Bootstrapping Flux GitOps (auto-deploys full ControlPlane)..."

    $fluxDir = Join-Path $PSScriptRoot "flux"

    if (-not (Test-Command "flux")) {
        Write-Step "Installing flux CLI..."
        if ($IsWindows) {
            winget install --id=Flux.Flux -e --source winget 2>$null
        } else {
            Invoke-Expression (Invoke-WebRequest -Uri "https://fluxcd.io/install.sh" -UseBasicParsing).Content
        }
    }

    # Create partner secrets in cluster
    kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic itl-controlplane-secrets `
        --namespace itl-platform `
        --from-literal=POSTGRES_PASSWORD=$($secrets.POSTGRES_PASSWORD) `
        --from-literal=NEO4J_PASSWORD=$($secrets.NEO4J_PASSWORD) `
        --from-literal=KEYCLOAK_ADMIN_PASSWORD=$($secrets.KEYCLOAK_ADMIN_PASSWORD) `
        --from-literal=JWT_SECRET=$($secrets.JWT_SECRET) `
        --dry-run=client -o yaml | kubectl apply -f -

    if ($DryRun) {
        Write-Warn "DRY RUN — flux bootstrap skipped"
        return
    }

    # Apply Flux GitRepository + Kustomization from local flux/ dir
    kubectl apply -f "$fluxDir/gotk-sync.yaml"
    kubectl apply -f "$fluxDir/kustomization.yaml"

    Write-OK "Flux GitOps bootstrap complete — stack will auto-deploy"
}

# ── Post-install summary ──────────────────────────────────────────────────────
function Show-Summary([hashtable]$secrets) {
    $domain = $script:Domain

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║   ITL ControlPlane — Installation Complete               ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Access your platform:" -ForegroundColor White
    switch ($script:Mode) {
        "docker" {
            Write-Host "    Portal       http://localhost:9052"
            Write-Host "    Dashboard    http://localhost:9051"
            Write-Host "    API Gateway  http://localhost:9050"
            Write-Host "    Keycloak     http://localhost:8080"
            Write-Host "    Neo4j        http://localhost:7474"
            Write-Host "    DB Manager   http://localhost:8978"
        }
        "k8s" {
            Write-Host "    Portal       https://$domain"
            Write-Host "    Dashboard    https://dashboard.$domain"
            Write-Host "    API Gateway  https://api.$domain"
            Write-Host "    Keycloak     https://iam.$domain"
        }
        "talos" {
            Write-Host "    Portal       https://$domain"
            Write-Host "    Dashboard    https://dashboard.$domain"
            Write-Host "    API Gateway  https://api.$domain"
            Write-Host "    Keycloak     https://iam.$domain"
            Write-Host ""
            Write-Host "    Talos config  $(Join-Path $PSScriptRoot 'talos/talosconfig')"
        }
    }
    Write-Host ""
    Write-Host "  Admin credentials:" -ForegroundColor White
    Write-Host "    User      $($secrets.ADMIN_EMAIL)"
    Write-Host "    Password  $($secrets.KEYCLOAK_ADMIN_PASSWORD)"
    Write-Host ""
    Write-Host "  Configuration saved to .env (do not commit this file)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Documentation: docs/PARTNER_INSTALL.md" -ForegroundColor DarkGray
    Write-Host ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
try {
    if (-not $Unattended) {
        Invoke-Wizard
    } else {
        Write-Banner
        # Validate required params for unattended
        if (-not $script:Mode)          { $script:Mode = "docker" }
        if (-not $script:PartnerName)   { Write-Fail "-PartnerName is required for unattended install"; exit 1 }
        if (-not $script:Domain)        { Write-Fail "-Domain is required for unattended install"; exit 1 }
        if (-not $script:AdminEmail)    { Write-Fail "-AdminEmail is required for unattended install"; exit 1 }
        if (-not $script:AdminPassword) { $script:AdminPassword = New-SecurePassword 24 }
    }

    if (-not $SkipPreflight) { Invoke-Preflight $script:Mode }

    $secrets = New-PartnerSecrets

    switch ($script:Mode) {
        "docker" { Install-Docker $secrets }
        "k8s"    { Install-K8s    $secrets }
        "talos"  { Install-Talos  $secrets }
    }

    Show-Summary $secrets

} catch {
    Write-Host ""
    Write-Fail "Installation failed: $_"
    Write-Fail $_.ScriptStackTrace
    exit 1
}
