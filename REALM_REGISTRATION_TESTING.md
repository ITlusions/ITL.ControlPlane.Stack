# 🧪 Testing Realm Registration with Local Keycloak Stack

## Quick Start (5 minutes)

### 1. Start the Full Stack

```bash
cd d:\repos\ITL.ControlPanel.Stack
docker-compose up -d
```

Wait for all services to be healthy:
```bash
docker-compose ps
```

Expected healthy services:
- ✅ postgres
- ✅ neo4j
- ✅ keycloak
- ✅ core-provider
- ✅ identity-provider
- ✅ api-gateway

### 2. Create a Test Realm in Keycloak

```powershell
cd d:\repos\ITL.ControlPanel.Stack
.\scripts\setup-keycloak-realm.ps1 -RealmName "test-realm"
```

This script will:
- ✅ Create a Keycloak realm called `test-realm`
- ✅ Create a test user (`testuser` / `TestPassword123!`)
- ✅ Create an OAuth2 client
- ✅ **Output the Realm ID (GUID)** - you'll need this!

**Example output:**
```
✓ Realm ID: 123e4567-e89b-12d3-a456-426614174000
```

### 3. Register the Realm with ITL

Get a default tenant ID first:

```powershell
# Get the default tenant ID
$realmId = "123e4567-e89b-12d3-a456-426614174000"  # From step 2
$tenantId = "12345678-1234-5678-1234-567812345678"  # Default tenant (update if needed)

.\scripts\test-realm-registration.ps1 `
    -RealmName "test-realm" `
    -RealmId $realmId `
    -TenantId $tenantId
```

Expected output:
```
✅ Registration Successful!

✓ Realm successfully registered with ITL
📋 Realm Details:
  Resource ID:  /providers/ITL.IAM/realms/test-realm
  Type:         ITL.IAM/realms
  Realm GUID:   123e4567-e89b-12d3-a456-426614174000
  Tenant:       12345678-1234-5678-1234-567812345678
  Primary:      True
```

---

## Detailed Setup Guide

### Prerequisites

**Required**:
- Docker Desktop (running)
- PowerShell 5.1 or higher
- Workspace: `d:\repos\ITL.ControlPanel.Stack`

**Services**:
- Keycloak: http://localhost:8080
- IAM Provider: http://localhost:8001
- Core Provider: http://localhost:8000
- API Gateway: http://localhost:9050

### Step-by-Step Testing

#### Step 1: Verify All Services Running

```powershell
cd d:\repos\ITL.ControlPanel.Stack

# Check status
docker-compose ps

# View logs
docker-compose logs -f keycloak          # Follow Keycloak logs
docker-compose logs -f identity-provider # Follow IAM Provider logs

# Health checks
Invoke-RestMethod -Uri "http://localhost:8080/health" -SkipCertificateCheck
Invoke-RestMethod -Uri "http://localhost:8001/health" -SkipCertificateCheck
Invoke-RestMethod -Uri "http://localhost:8000/health" -SkipCertificateCheck
```

#### Step 2: Login to Keycloak Admin Console

```
URL:      http://localhost:8080
Username: admin
Password: admin
```

1. Click **Administration Console**
2. You should see:
   - Master realm (default)
   - List of custom realms

#### Step 3: Create Test Realm (Using Script)

```powershell
# Option A: Run the automated setup script
.\scripts\setup-keycloak-realm.ps1 -RealmName "my-first-realm"

# Option B: Manually create via UI
# 1. In Keycloak admin console
# 2. Hover over "Master" realm dropdown (top left)
# 3. Click "Create Realm"
# 4. Name: my-first-realm
# 5. Create
```

#### Step 4: Get the Realm ID

**From Script Output** (easiest):
```
✓ Realm ID: 123e4567-e89b-12d3-a456-426614174000
```

**From Keycloak UI** (manual):
1. Go to http://localhost:8080/admin
2. Select your realm from dropdown
3. Go to **Realm Settings** → **General** tab
4. Copy the **ID** field

#### Step 5: Get Your Tenant ID

Find the default tenant ID from the Core Provider:

```powershell
# Query Core Provider for tenants
Invoke-RestMethod -Uri "http://localhost:8000/providers/ITL.Core/tenants" `
    -Method Get `
    -SkipCertificateCheck | ConvertTo-Json | Select-Object -First 100
```

Or use the default test tenant:
```
12345678-1234-5678-1234-567812345678
```

#### Step 6: Register the Realm with ITL

**Using the test script**:
```powershell
.\scripts\test-realm-registration.ps1 `
    -RealmName "my-first-realm" `
    -RealmId "123e4567-e89b-12d3-a456-426614174000" `
    -TenantId "12345678-1234-5678-1234-567812345678"
```

**Using curl directly**:
```bash
curl -X POST http://localhost:8001/providers/ITL.IAM/realms/register-existing \
  -H "X-User-Id: admin" \
  -H "X-Tenant-Id: 12345678-1234-5678-1234-567812345678" \
  -H "Content-Type: application/json" \
  -d '{
    "realm_name": "my-first-realm",
    "realm_id": "123e4567-e89b-12d3-a456-426614174000",
    "tenant_id": "12345678-1234-5678-1234-567812345678",
    "display_name": "My First Realm",
    "is_primary": true
  }'
```

**Using PowerShell directly**:
```powershell
$body = @{
    realm_name = "my-first-realm"
    realm_id = "123e4567-e89b-12d3-a456-426614174000"
    tenant_id = "12345678-1234-5678-1234-567812345678"
    display_name = "My First Realm"
    is_primary = $true
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8001/providers/ITL.IAM/realms/register-existing" `
    -Method Post `
    -ContentType "application/json" `
    -Headers @{
        "X-User-Id" = "admin"
        "X-Tenant-Id" = "12345678-1234-5678-1234-567812345678"
    } `
    -Body $body `
    -SkipCertificateCheck
```

#### Step 7: Verify Registration

**List all realms via API**:
```powershell
Invoke-RestMethod -Uri "http://localhost:8001/providers/ITL.IAM/realms" `
    -Method Get `
    -SkipCertificateCheck | ConvertTo-Json
```

**Check database directly** (if needed):
```powershell
# Connect to postgres
docker exec -it itl-postgres psql -U controlplane -d controlplane -c \
  "SELECT * FROM realms WHERE realm_name = 'my-first-realm';"
```

---

## Troubleshooting

### ❌ Connection Refused (Keycloak not running)

```powershell
# Check service status
docker-compose ps keycloak

# Start if stopped
docker-compose up -d keycloak

# Check logs
docker-compose logs -f keycloak
```

### ❌ Authentication Failed (admin/admin not working)

```powershell
# Wait for Keycloak to fully initialize
Start-Sleep -Seconds 30

# Check health endpoint
Invoke-RestMethod -Uri "http://localhost:8080/health/ready" -SkipCertificateCheck
```

### ❌ Realm Already Exists

The script is idempotent - running again won't fail, it will return the existing realm.

### ❌ Registration Returns 400 Error

```powershell
# Verify IAM Provider is healthy
Invoke-RestMethod -Uri "http://localhost:8001/health" -SkipCertificateCheck

# Check logs
docker-compose logs -f identity-provider | Select-Object -Last 50

# Verify tenant exists
docker-compose exec -T postgres psql -U controlplane -d controlplane -c \
  "SELECT * FROM tenants WHERE id = '12345678-1234-5678-1234-567812345678';"
```

### ❌ Tenant Not Found

Create a tenant in Core Provider first:

```powershell
$tenantBody = @{
    name = "my-tenant"
    display_name = "My Organization"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8000/providers/ITL.Core/tenants" `
    -Method Post `
    -ContentType "application/json" `
    -Body $tenantBody `
    -SkipCertificateCheck
```

---

## One-Liner Testing

**Quick test (create and register in one go)**:

```powershell
$realm="test-realm"; 
$tenantId="12345678-1234-5678-1234-567812345678"; 
.\scripts\setup-keycloak-realm.ps1 -RealmName $realm; 
Start-Sleep -Seconds 5; 
$realmId = $(Invoke-RestMethod -Uri "http://localhost:8080/realms/$realm" -SkipCertificateCheck).id; 
.\scripts\test-realm-registration.ps1 -RealmName $realm -RealmId $realmId -TenantId $tenantId
```

---

## What Gets Created

### In Keycloak
- ✅ Realm: `test-realm` with ID (GUID)
- ✅ User: `testuser` / `TestPassword123!`
- ✅ OAuth2 Client: `itl-test-client`
- ✅ Roles and permissions (optional)

### In ITL ControlPlane
- ✅ Realm Resource: `/providers/ITL.IAM/realms/test-realm`
- ✅ 1:1 Mapping: Keycloak realm_id ↔ ITL tenant_id
- ✅ Database Record: Stored in `realms` table
- ✅ Audit Trail: All operations logged

---

## Next Steps

After successful registration:

1. **List realms** via API:
   ```powershell
   Invoke-RestMethod -Uri "http://localhost:8001/providers/ITL.IAM/realms" -SkipCertificateCheck
   ```

2. **Get specific realm**:
   ```powershell
   Invoke-RestMethod -Uri "http://localhost:8001/providers/ITL.IAM/realms/test-realm" -SkipCertificateCheck
   ```

3. **Create users in the realm**:
   - Via Keycloak UI: http://localhost:8080
   - Via Keycloak Admin API

4. **Link users to rules/groups**:
   - Create groups in Keycloak
   - Configure RBAC via ITL

---

## Reference

### Default Credentials

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| Keycloak | http://localhost:8080 | admin | admin |
| pgAdmin | N/A | controlplane | devpassword |
| Neo4j | N/A | neo4j | devpassword |

### Default Tenant ID

```
12345678-1234-5678-1234-567812345678
```

Override via environment variable:
```powershell
$env:DEFAULT_TENANT_ID = "your-tenant-id"
```

### Database Schema

**Realms Table** (PostgreSQL):
```sql
CREATE TABLE realms (
  id UUID PRIMARY KEY,
  realm_name VARCHAR NOT NULL UNIQUE,
  realm_id UUID NOT NULL,          -- Keycloak GUID
  tenant_id UUID,                  -- ITL Tenant GUID
  display_name VARCHAR,
  description TEXT,
  is_primary BOOLEAN DEFAULT false,
  enabled BOOLEAN DEFAULT true,
  properties JSONB,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

---

## Getting Help

If issues persist:

1. **Check all service logs**:
   ```powershell
   docker-compose logs --tail=50
   ```

2. **Restart services**:
   ```powershell
   docker-compose restart identity-provider core-provider keycloak
   ```

3. **Full stack reset** (⚠️ deletes data):
   ```powershell
   docker-compose down -v
   docker-compose up -d
   ```

4. **Check the ITL documentation**:
   - SDK: [ITL.ControlPanel.SDK/README.md](../../ITL.ControlPanel.SDK/README.md)
   - IAM Provider: [ITL.ControlPlane.ResourceProvider.Identity/README.md](../../ITL.ControlPlane.ResourceProvider.Identity/README.md)

