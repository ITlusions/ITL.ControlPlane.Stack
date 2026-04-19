#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automated Keycloak realm setup for ITL testing

.DESCRIPTION
    Creates a test realm in Keycloak with OAuth2 clients and users
    for testing realm registration

.PARAMETER RealmName
    Name of the realm to create (default: test-realm)

.PARAMETER KeycloakUrl
    Keycloak URL (default: http://localhost:8080)

.PARAMETER AdminUser
    Keycloak admin username (default: admin)

.PARAMETER AdminPassword
    Keycloak admin password (default: admin)

.EXAMPLE
    .\setup-keycloak-realm.ps1 -RealmName "my-test-realm"
#>

param(
    [string]$RealmName = "test-realm",
    [string]$KeycloakUrl = "http://localhost:8080",
    [string]$AdminUser = "admin",
    [string]$AdminPassword = "admin",
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

Write-Host "🔧 ITL Keycloak Realm Setup" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Realm Name: $RealmName"
Write-Host "Keycloak URL: $KeycloakUrl"
Write-Host ""

# ────────────────────────────────────────
# 1. Get Admin Token
# ────────────────────────────────────────

Write-Host "📝 Step 1: Obtaining admin token..." -ForegroundColor Yellow

$tokenUrl = "$KeycloakUrl/realms/master/protocol/openid-connect/token"
$tokenBody = @{
    grant_type    = "password"
    client_id     = "admin-cli"
    username      = $AdminUser
    password      = $AdminPassword
} | ConvertTo-Json

try {
    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl `
        -Method Post `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "grant_type=password&client_id=admin-cli&username=$AdminUser&password=$AdminPassword" `
        -SkipCertificateCheck
    
    $accessToken = $tokenResponse.access_token
    Write-Host "✓ Token obtained successfully" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to get token: $_" -ForegroundColor Red
    Write-Host "  Make sure Keycloak is running at: $KeycloakUrl" -ForegroundColor Red
    exit 1
}

# ────────────────────────────────────────
# 2. Create Realm
# ────────────────────────────────────────

Write-Host "🏗️  Step 2: Creating realm '$RealmName'..." -ForegroundColor Yellow

$realmUrl = "$KeycloakUrl/admin/realms"
$realmBody = @{
    realm       = $RealmName
    displayName = "$RealmName (Test Realm)"
    enabled     = $true
    sslRequired = "none"
    bruteForceProtected = $false
} | ConvertTo-Json

try {
    $realmResponse = Invoke-RestMethod -Uri $realmUrl `
        -Method Post `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -Body $realmBody `
        -SkipCertificateCheck
    
    Write-Host "✓ Realm '$RealmName' created successfully" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "⚠️  Realm '$RealmName' already exists" -ForegroundColor Yellow
    } else {
        Write-Host "✗ Failed to create realm: $_" -ForegroundColor Red
        exit 1
    }
}

# ────────────────────────────────────────
# 3. Get Realm ID
# ────────────────────────────────────────

Write-Host "🔍 Step 3: Getting realm ID..." -ForegroundColor Yellow

$getRealmsUrl = "$KeycloakUrl/admin/realms/$RealmName"

try {
    $realmInfo = Invoke-RestMethod -Uri $getRealmsUrl `
        -Method Get `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -SkipCertificateCheck
    
    $realmId = $realmInfo.id
    Write-Host "✓ Realm ID: $realmId" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to get realm ID: $_" -ForegroundColor Red
    exit 1
}

# ────────────────────────────────────────
# 4. Create Test User
# ────────────────────────────────────────

Write-Host "👤 Step 4: Creating test user..." -ForegroundColor Yellow

$testUsername = "testuser"
$testEmail = "testuser@example.com"
$testPassword = "TestPassword123!"

$userUrl = "$KeycloakUrl/admin/realms/$RealmName/users"
$userBody = @{
    username    = $testUsername
    email       = $testEmail
    firstName   = "Test"
    lastName    = "User"
    enabled     = $true
    emailVerified = $true
} | ConvertTo-Json

try {
    $userResponse = Invoke-RestMethod -Uri $userUrl `
        -Method Post `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -Body $userBody `
        -SkipCertificateCheck
    
    Write-Host "✓ Test user '$testUsername' created" -ForegroundColor Green
    
    # Set password
    $userId = $userResponse.id
    $passwordUrl = "$KeycloakUrl/admin/realms/$RealmName/users/$userId/reset-password"
    $passwordBody = @{
        type      = "password"
        value     = $testPassword
        temporary = $false
    } | ConvertTo-Json
    
    Invoke-RestMethod -Uri $passwordUrl `
        -Method Post `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -Body $passwordBody `
        -SkipCertificateCheck | Out-Null
    
    Write-Host "✓ Password set: $testPassword" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "⚠️  User '$testUsername' already exists" -ForegroundColor Yellow
    } else {
        Write-Host "⚠️  Warning: Could not create user: $_" -ForegroundColor Yellow
    }
}

# ────────────────────────────────────────
# 5. Create OAuth2 Client
# ────────────────────────────────────────

Write-Host "🔐 Step 5: Creating OAuth2 client..." -ForegroundColor Yellow

$clientId = "itl-test-client"
$clientUrl = "$KeycloakUrl/admin/realms/$RealmName/clients"
$clientBody = @{
    clientId            = $clientId
    name                = "ITL Test Client"
    enabled             = $true
    publicClient        = $false
    serviceAccountsEnabled = $true
    directAccessGrantsEnabled = $true
    standardFlowEnabled = $true
    implicitFlowEnabled = $false
    redirectUris        = @("http://localhost:3000/*", "http://localhost:8080/*")
    webOrigins          = @("*")
} | ConvertTo-Json

try {
    $clientResponse = Invoke-RestMethod -Uri $clientUrl `
        -Method Post `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -Body $clientBody `
        -SkipCertificateCheck
    
    $clientUuid = $clientResponse.id
    Write-Host "✓ OAuth2 client '$clientId' created (UUID: $clientUuid)" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "⚠️  Client '$clientId' already exists" -ForegroundColor Yellow
        # Get the client ID
        $clients = Invoke-RestMethod -Uri "$clientUrl?clientId=$clientId" `
            -Method Get `
            -Headers @{ Authorization = "Bearer $accessToken" } `
            -SkipCertificateCheck
        $clientUuid = $clients[0].id
    } else {
        Write-Host "⚠️  Warning: Could not create client: $_" -ForegroundColor Yellow
    }
}

# ────────────────────────────────────────
# 6. Get Client Secret
# ────────────────────────────────────────

if ($clientUuid) {
    Write-Host "🔑 Step 6: Getting client credentials..." -ForegroundColor Yellow
    
    try {
        $secretUrl = "$KeycloakUrl/admin/realms/$RealmName/clients/$clientUuid/client-secret"
        $secretResponse = Invoke-RestMethod -Uri $secretUrl `
            -Method Get `
            -Headers @{ Authorization = "Bearer $accessToken" } `
            -SkipCertificateCheck
        
        $clientSecret = $secretResponse.value
        Write-Host "✓ Client secret obtained" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Warning: Could not get client secret: $_" -ForegroundColor Yellow
    }
}

# ────────────────────────────────────────
# 7. Summary
# ────────────────────────────────────────

Write-Host ""
Write-Host "✅ Keycloak Setup Complete!" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Realm Configuration:" -ForegroundColor Cyan
Write-Host "  Realm Name:     $RealmName"
Write-Host "  Realm ID:       $realmId"
Write-Host "  Keycloak URL:   $KeycloakUrl"
Write-Host ""
Write-Host "👤 Test User:" -ForegroundColor Cyan
Write-Host "  Username:       $testUsername"
Write-Host "  Password:       $testPassword"
Write-Host "  Email:          $testEmail"
Write-Host ""
Write-Host "🔐 OAuth2 Client:" -ForegroundColor Cyan
Write-Host "  Client ID:      $clientId"
if ($clientSecret) {
    Write-Host "  Client Secret:  $clientSecret"
}
Write-Host ""
Write-Host "🚀 Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Use the Realm ID to register the realm:"
Write-Host ""
Write-Host "     curl -X POST http://localhost:8080/providers/ITL.IAM/realms/register-existing \"
Write-Host "       -H 'X-User-Id: admin' \"
Write-Host "       -H 'X-Tenant-Id: [your-tenant-id]' \"
Write-Host "       -H 'Content-Type: application/json' \"
Write-Host "       -d '{" -NoNewline
Write-Host ""
Write-Host "         \"realm_name\": \"$RealmName\","
Write-Host "         \"realm_id\": \"$realmId\","
Write-Host "         \"tenant_id\": \"[your-tenant-id]\","
Write-Host "         \"display_name\": \"$RealmName\","
Write-Host "         \"is_primary\": true"
Write-Host "       }'"
Write-Host ""
Write-Host "  2. Or use the PowerShell helper:"
Write-Host ""
Write-Host "     .\test-realm-registration.ps1 -RealmName '$RealmName' -RealmId '$realmId'"
Write-Host ""
