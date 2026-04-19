# Identity Provider Deployment Guide

## Overview

The Identity Provider is now integrated into the ITL ControlPlane stack, providing centralized identity management with multi-backend support (Keycloak, Azure AD, Okta).

## Quick Start

### Start the Full Stack

```powershell
cd D:\repos\ITL.ControlPlane.Stack
docker compose up -d
```

### Start Only Identity Provider + Dependencies

```powershell
docker compose up -d postgres neo4j identity-provider
```

### View Identity Provider Logs

```powershell
docker compose logs -f identity-provider
```

### Stop and Clean Up

```powershell
docker compose down -v
```

## Service Details

### Identity Provider
- **Container**: `itl-identity-provider`
- **Internal Port**: 8000
- **External Port**: 8001
- **Health Check**: `http://localhost:8001/health`
- **Ready Check**: `http://localhost:8001/health/ready`
- **API Docs**: `http://localhost:8001/docs`

### Configuration

#### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgresql+asyncpg://...` | PostgreSQL connection string |
| `IDENTITY_BACKEND` | `keycloak` | Identity backend: keycloak, azure_ad, okta |
| `KEYCLOAK_URL` | `https://sts.itlusions.com` | Keycloak server URL |
| `KEYCLOAK_REALM` | `master` | Keycloak realm |
| `KEYCLOAK_CLIENT_ID` | `admin-cli` | Keycloak client ID |
| `KEYCLOAK_USERNAME` | `admin` | Keycloak admin username |
| `KEYCLOAK_PASSWORD` | `changeme` | Keycloak admin password |
| `CONTROLPLANE_API_URL` | `http://api-gateway:8080` | API Gateway URL |
| `GATEWAY_REGISTRATION_ENABLED` | `true` | Auto-register with gateway |

#### Override Variables

Create a `.env` file in the stack directory:

```bash
# .env
KEYCLOAK_ADMIN_PASSWORD=your-secure-password
IDENTITY_BACKEND=keycloak
```

## API Endpoints

The Identity Provider exposes simplified ARM-style endpoints:

### Realms
- `POST /realms` - Create realm
- `GET /realms` - List realms
- `GET /realms/{name}` - Get realm
- `DELETE /realms/{name}` - Delete realm
- `PATCH /realms/{name}` - Update realm

### Users
- `POST /users` - Create user
- `GET /users` - List users
- `GET /users/{username}` - Get user
- `DELETE /users/{username}` - Delete user
- `PATCH /users/{username}` - Update user

### Clients
- `POST /clients` - Create client
- `GET /clients` - List clients
- `GET /clients/{clientId}` - Get client
- `DELETE /clients/{clientId}` - Delete client
- `PATCH /clients/{clientId}` - Update client

### Roles
- `POST /roles` - Create role
- `GET /roles` - List roles
- `GET /roles/{name}` - Get role
- `DELETE /roles/{name}` - Delete role
- `PATCH /roles/{name}` - Update role

### Groups
- `POST /groups` - Create group
- `GET /groups` - List groups
- `GET /groups/{name}` - Get group
- `DELETE /groups/{name}` - Delete group
- `PATCH /groups/{name}` - Update group

### Service Accounts
- `POST /serviceaccounts` - Create service account
- `GET /serviceaccounts` - List service accounts
- `GET /serviceaccounts/{name}` - Get service account
- `DELETE /serviceaccounts/{name}` - Delete service account
- `PATCH /serviceaccounts/{name}` - Update service account

## Example Usage

### Via API Gateway (ARM-style)

```bash
# Create a realm
curl -X POST http://localhost:9050/subscriptions/sub-123/resourceGroups/rg-test/providers/ITL.Identity/realms \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-realm",
    "location": "westeurope",
    "properties": {
      "enabled": true,
      "displayName": "My Organization Realm"
    },
    "tags": {
      "environment": "production"
    }
  }'

# Create a user
curl -X POST http://localhost:9050/subscriptions/sub-123/resourceGroups/rg-test/providers/ITL.Identity/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "john.doe",
    "properties": {
      "username": "john.doe",
      "email": "john.doe@example.com",
      "firstName": "John",
      "lastName": "Doe",
      "enabled": true
    }
  }'
```

### Direct to Provider (Simplified)

```bash
# Create a realm (direct)
curl -X POST http://localhost:8001/realms \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-realm",
    "properties": {
      "enabled": true,
      "displayName": "My Organization Realm"
    }
  }'

# List realms
curl http://localhost:8001/realms

# Get specific realm
curl http://localhost:8001/realms/my-realm

# Delete realm
curl -X DELETE http://localhost:8001/realms/my-realm
```

## Health Checks

### Kubernetes Liveness Probe

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 5
  periodSeconds: 10
```

### Kubernetes Readiness Probe

```yaml
readinessProbe:
  httpGet:
    path: /health/ready
    port: 8000
  initialDelaySeconds: 15
  periodSeconds: 5
```

## Troubleshooting

### Check Service Status

```powershell
# Check if running
docker compose ps identity-provider

# View logs
docker compose logs -f identity-provider

# Check health
curl http://localhost:8001/health/ready
```

### Expected Health Response

```json
{
  "status": "healthy",
  "components": [
    {
      "name": "database",
      "status": "healthy",
      "message": "Database connection successful",
      "latency_ms": 12.5
    }
  ],
  "timestamp": "2026-02-12T10:30:00Z",
  "version": "1.0.0"
}
```

### Common Issues

#### 1. Provider Not Starting

**Symptom**: Container exits immediately

**Check**:
```powershell
docker compose logs identity-provider
```

**Solution**: Ensure PostgreSQL is healthy
```powershell
docker compose up -d postgres
docker compose logs postgres
```

#### 2. Cannot Connect to Keycloak

**Symptom**: Warnings about stub mode in logs

**Check**:
```powershell
curl https://sts.itlusions.com -I
```

**Solution**: Verify Keycloak URL and credentials in environment variables

#### 3. API Gateway Not Finding Provider

**Symptom**: 404 errors when accessing through gateway

**Check**: Provider registration
```bash
curl http://localhost:9050/api/providers
```

**Solution**: Restart identity provider to re-register
```powershell
docker compose restart identity-provider
```

## Architecture

```
┌─────────────────┐
│   Dashboard     │
│   :9051         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  API Gateway    │────▶│  Core Provider   │
│  :9050          │     │  :8000           │
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  Identity       │────▶│  Keycloak        │
│  Provider       │     │  sts.itlusions   │
│  :8001          │     │  .com            │
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  PostgreSQL     │     │  Neo4j           │
│  :5432          │     │  :7687           │
└─────────────────┘     └──────────────────┘
```

## Identity Backend Support

### Keycloak (Production Ready ✅)
- Full CRUD operations for realms, users, clients, roles, groups
- OAuth2 authentication
- Supports master realm and custom realms

### Azure AD (Stub 🚧)
- Framework in place
- Ready for Microsoft Graph API implementation
- Requires `azure-identity` and `msgraph-sdk` packages

### Okta (Stub 🚧)
- Framework in place
- Ready for Okta Management API implementation
- Requires `okta-sdk-python` package

## Integration with SDK

The Identity Provider uses the enhanced SDK features:

1. **Identity Backends** from `itl_controlplane_sdk.identity`
   ```python
   from itl_controlplane_sdk.identity import KeycloakIdentityBackend
   backend = KeycloakIdentityBackend(config)
   ```

2. **Generic Models** for consistent API schemas
   ```python
   from itl_controlplane_sdk.core.models import GenericCreateRequest
   ```

3. **Provider Helpers** for health checks and observability
   ```python
   from itl_controlplane_sdk.providers import create_health_check_routes
   ```

## Metrics

Prometheus metrics exposed on port 9090 (if enabled):

- `provider_requests_total{provider, resource_type, operation, status}`
- `provider_request_duration_seconds{provider, resource_type, operation}`
- `provider_active_requests{provider, resource_type}`

## Development

### Rebuild After Changes

```powershell
docker compose up -d --build identity-provider
```

### Run Locally (Outside Docker)

```powershell
cd D:\repos\ITL.ControlPlane.ResourceProvider.Identity

# Set environment variables
$env:DATABASE_URL = "postgresql+asyncpg://controlplane:devpassword@localhost:5432/controlplane"
$env:KEYCLOAK_URL = "https://sts.itlusions.com"
$env:KEYCLOAK_REALM = "master"
$env:KEYCLOAK_USERNAME = "admin"
$env:KEYCLOAK_PASSWORD = "changeme"

# Run
python entrypoint.py
```

### Run Tests

```powershell
cd D:\repos\ITL.ControlPlane.ResourceProvider.Identity
pytest tests/ -v
```

## Next Steps

1. **Configure Production Keycloak**: Update environment variables for production
2. **Add Custom Realms**: Create organization-specific realms
3. **Integrate with Dashboard**: Enable SSO via Identity Provider
4. **Add RBAC Policies**: Define access control rules
5. **Monitor Metrics**: Connect Prometheus for observability

## Resources

- [Identity Provider README](../ITL.ControlPlane.ResourceProvider.Identity/README.md)
- [SDK Enhancement Summary](../ITL.ControlPlane.SDK/SDK_ENHANCEMENT_SUMMARY.md)
- [SDK Quick Reference](../ITL.ControlPlane.SDK/SDK_QUICK_REFERENCE.md)
- [Keycloak Admin API](https://www.keycloak.org/docs-api/latest/rest-api/)

---

**Last Updated**: February 12, 2026  
**Version**: 1.0.0
