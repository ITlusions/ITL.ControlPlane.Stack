#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test ITL realm registration endpoint

.DESCRIPTION
    Registers an existing Keycloak realm with ITL ControlPlane

.PARAMETER RealmName
    Name of the Keycloak realm (default: test-realm)

.PARAMETER RealmId
    Keycloak realm ID/UUID (can be obtained from setup script)

.PARAMETER TenantId
    ITL tenant ID to link to (default: uses default tenant)

.PARAMETER IamProviderUrl
    IAM Provider URL (default: http://localhost:8001)

.PARAMETER UserId
    User ID for audit trail (default: test-user)

.EXAMPLE
    .\test-realm-registration.ps1 -RealmName "test-realm" -RealmId "abc123..." -TenantId "tenant-456"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$RealmName = "test-realm",
    
    [Parameter(Mandatory=$false)]
    [string]$RealmId,
    
    [Parameter(Mandatory=$false)]
    [string]$TenantId = "12345678-1234-5678-1234-567812345678",
    
    [string]$IamProviderUrl = "http://localhost:8001",
    
    [string]$UserId = "test-user"
)

$ErrorActionPreference = "Stop"

Write-Host "🧪 Testing Realm Registration" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Validate inputs
if (-not $RealmId) {
    Write-Host "⚠️  RealmId not provided. Getting from Keycloak..." -ForegroundColor Yellow
    
    # Try to get the realm ID from Keycloak
    $keycloakUrl = "http://localhost:8080"
    $attemptUrl = "$keycloakUrl/realms/$RealmName"
    
    try {
        $realmInfo = Invoke-RestMethod -Uri $attemptUrl -SkipCertificateCheck
        $RealmId = $realmInfo.id
        Write-Host "✓ Found Realm ID: $RealmId" -ForegroundColor Green
    } catch {
        Write-Host "✗ Could not find realm. Please run setup-keycloak-realm.ps1 first" -ForegroundColor Red
        Write-Host "  Usage: .\setup-keycloak-realm.ps1 -RealmName '$RealmName'" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Realm Name:       $RealmName"
Write-Host "  Realm ID:         $RealmId"
Write-Host "  Tenant ID:        $TenantId"
Write-Host "  IAM Provider:     $IamProviderUrl"
Write-Host "  User ID:          $UserId"
Write-Host ""

# ────────────────────────────────────────
# Register Realm
# ────────────────────────────────────────

Write-Host "📤 Registering realm with ITL..." -ForegroundColor Yellow

$registrationUrl = "$IamProviderUrl/providers/ITL.IAM/realms/register-existing"

$registerBody = @{
    realm_name   = $RealmName
    realm_id     = $RealmId
    tenant_id    = $TenantId
    display_name = "Test Realm - $RealmName"
    description  = "Realm automatically registered for testing"
    is_primary   = $true
} | ConvertTo-Json

Write-Host "Request URL: $registrationUrl" -ForegroundColor Gray
Write-Host "Request Body:" -ForegroundColor Gray
Write-Host $registerBody -ForegroundColor Gray
Write-Host ""

try {
    $response = Invoke-RestMethod -Uri $registrationUrl `
        -Method Post `
        -ContentType "application/json" `
        -Headers @{
            "X-User-Id" = $UserId
            "X-Tenant-Id" = $TenantId
        } `
        -Body $registerBody `
        -SkipCertificateCheck
    
    Write-Host "✅ Registration Successful!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Response:" -ForegroundColor Cyan
    Write-Host ($response | ConvertTo-Json -Depth 10) -ForegroundColor Gray
    
    if ($response.success -eq $true) {
        Write-Host ""
        Write-Host "✓ Realm successfully registered with ITL" -ForegroundColor Green
        
        if ($response.realm) {
            Write-Host ""
            Write-Host "📋 Realm Details:" -ForegroundColor Cyan
            Write-Host "  Resource ID:  $($response.realm.id)"
            Write-Host "  Type:         $($response.realm.type)"
            Write-Host "  Realm GUID:   $($response.realm.properties.realm_id)"
            Write-Host "  Tenant:       $($response.realm.properties.tenant_id)"
            Write-Host "  Primary:      $($response.realm.properties.is_primary)"
        }
    }
} catch {
    Write-Host "❌ Registration Failed!" -ForegroundColor Red
    Write-Host ""
    
    try {
        $errorDetail = $_ | ConvertFrom-Json
        Write-Host "Error Response:" -ForegroundColor Red
        Write-Host ($errorDetail | ConvertTo-Json -Depth 10)
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Response: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "💡 Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Check IAM Provider is running: $IamProviderUrl/health" -ForegroundColor Yellow
    Write-Host "  2. Verify realm exists in Keycloak: http://localhost:8080" -ForegroundColor Yellow
    Write-Host "  3. Confirm TenantId exists: $TenantId" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "🎉 Test Complete!" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
