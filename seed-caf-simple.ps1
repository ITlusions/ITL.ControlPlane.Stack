<#
.SYNOPSIS
    Seed simple CAF structure with 2 tenants, 2 locations, subscriptions, and resource groups.
    No management groups, no policies.
#>

param(
    [string]$BaseUrl = "http://localhost:8001"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   ITL ControlPlane CAF Seed Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Helper function to create resources
function New-Resource {
    param([string]$Endpoint, [hashtable]$Body, [string]$Label)
    try {
        $json = $Body | ConvertTo-Json -Depth 10
        $result = Invoke-RestMethod -Uri "$BaseUrl$Endpoint" -Method POST -Body $json -ContentType "application/json" -ErrorAction Stop
        Write-Host "[OK] Created $Label" -ForegroundColor Green
        return $result
    } catch {
        $errorDetail = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $errorDetail = $_.ErrorDetails.Message }
        Write-Host "[FAIL] $Label - $errorDetail" -ForegroundColor Red
        return $null
    }
}


# ========================================
# Step 1: Create Locations
# ========================================
Write-Host "`n[1/4] Creating Locations..." -ForegroundColor Yellow

New-Resource -Endpoint "/resources/locations" -Body @{
    name = "westeurope"
    display_name = "West Europe"
    geography = "Europe"
    geography_group = "Europe"
    location = "global"
} -Label "Location: westeurope"

New-Resource -Endpoint "/resources/locations" -Body @{
    name = "northeurope"
    display_name = "North Europe"
    geography = "Europe"
    geography_group = "Europe"
    location = "global"
} -Label "Location: northeurope"


# ========================================
# Step 2: Create Tenants
# ========================================
Write-Host "`n[2/4] Creating Tenants..." -ForegroundColor Yellow

$itlTenant = New-Resource -Endpoint "/resources/tenants" -Body @{
    name = "ITL"
    display_name = "ITL Production"
    location = "global"
} -Label "Tenant: ITL"

$itlDevTenant = New-Resource -Endpoint "/resources/tenants" -Body @{
    name = "ITL-Dev"
    display_name = "ITL Development"
    location = "global"
} -Label "Tenant: ITL-Dev"

# Get tenant IDs (use resource_guid or extract from id)
$itlTenantId = if ($itlTenant.tenant_id) { $itlTenant.tenant_id } elseif ($itlTenant.resource_guid) { $itlTenant.resource_guid } else { "ITL" }
$itlDevTenantId = if ($itlDevTenant.tenant_id) { $itlDevTenant.tenant_id } elseif ($itlDevTenant.resource_guid) { $itlDevTenant.resource_guid } else { "ITL-Dev" }

Write-Host "  ITL Tenant ID: $itlTenantId" -ForegroundColor Gray
Write-Host "  ITL-Dev Tenant ID: $itlDevTenantId" -ForegroundColor Gray

# ========================================
# Step 3: Create Subscriptions (CAF pattern)
# ========================================
Write-Host "`n[3/4] Creating Subscriptions (CAF pattern)..." -ForegroundColor Yellow

# ITL Tenant Subscriptions (Production CAF)
$subscriptions = @()

# Platform subscriptions
$subs = @(
    @{ Name = "itl-platform-connectivity"; Display = "ITL Platform - Connectivity"; Tenant = $itlTenantId; Location = "westeurope" },
    @{ Name = "itl-platform-identity"; Display = "ITL Platform - Identity"; Tenant = $itlTenantId; Location = "westeurope" },
    @{ Name = "itl-platform-management"; Display = "ITL Platform - Management"; Tenant = $itlTenantId; Location = "westeurope" },
    # Landing zone subscriptions
    @{ Name = "itl-lz-prod-001"; Display = "ITL Landing Zone - Prod 001"; Tenant = $itlTenantId; Location = "westeurope" },
    @{ Name = "itl-lz-prod-002"; Display = "ITL Landing Zone - Prod 002"; Tenant = $itlTenantId; Location = "northeurope" },
    # ITL-Dev Tenant Subscriptions (Development CAF)
    @{ Name = "itldev-platform-connectivity"; Display = "ITL-Dev Platform - Connectivity"; Tenant = $itlDevTenantId; Location = "westeurope" },
    @{ Name = "itldev-platform-identity"; Display = "ITL-Dev Platform - Identity"; Tenant = $itlDevTenantId; Location = "westeurope" },
    @{ Name = "itldev-lz-dev-001"; Display = "ITL-Dev Landing Zone - Dev 001"; Tenant = $itlDevTenantId; Location = "westeurope" },
    @{ Name = "itldev-lz-test-001"; Display = "ITL-Dev Landing Zone - Test 001"; Tenant = $itlDevTenantId; Location = "northeurope" }
)

foreach ($sub in $subs) {
    $result = New-Resource -Endpoint "/resources/subscriptions" -Body @{
        name = $sub.Name
        display_name = $sub.Display
        tenant_id = "/providers/ITL.Core/tenants/$($sub.Tenant)"
        location = $sub.Location
        state = "Enabled"
    } -Label "Subscription: $($sub.Name)"
    
    if ($result) {
        $subId = if ($result.subscription_id) { $result.subscription_id } elseif ($result.resource_guid) { $result.resource_guid } else { $sub.Name }
        $subscriptions += @{ Name = $sub.Name; Id = $subId; Location = $sub.Location }
    }
}

# ========================================
# Step 4: Create Resource Groups
# ========================================
Write-Host "`n[4/4] Creating Resource Groups..." -ForegroundColor Yellow

# Resource groups per subscription
$rgMapping = @{
    "itl-platform-connectivity" = @("rg-hub-network", "rg-firewall", "rg-dns")
    "itl-platform-identity" = @("rg-identity", "rg-keyvault")
    "itl-platform-management" = @("rg-monitoring", "rg-automation", "rg-backup")
    "itl-lz-prod-001" = @("rg-app-frontend", "rg-app-backend", "rg-data")
    "itl-lz-prod-002" = @("rg-app-api", "rg-app-worker")
    "itldev-platform-connectivity" = @("rg-hub-network-dev", "rg-firewall-dev")
    "itldev-platform-identity" = @("rg-identity-dev")
    "itldev-lz-dev-001" = @("rg-dev-app", "rg-dev-data")
    "itldev-lz-test-001" = @("rg-test-app", "rg-test-data")
}

foreach ($subInfo in $subscriptions) {
    $subName = $subInfo.Name
    $subId = $subInfo.Id
    $location = $subInfo.Location
    
    if ($rgMapping.ContainsKey($subName)) {
        foreach ($rgName in $rgMapping[$subName]) {
            New-Resource -Endpoint "/subscriptions/$subId/resourceGroups" -Body @{
                name = $rgName
                location = $location
            } -Label "ResourceGroup: $rgName (in $subName)"
        }
    }
}

# ========================================
# Summary
# ========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   Seed Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nCreated:" -ForegroundColor Green
Write-Host "  - 2 Tenants (ITL, ITL-Dev)"
Write-Host "  - 2 Locations (westeurope, northeurope)"
Write-Host "  - 9 Subscriptions (CAF pattern)"
Write-Host "  - Multiple Resource Groups per subscription"
Write-Host "`nVerify at: http://localhost:9051/resources/tenants" -ForegroundColor Gray
