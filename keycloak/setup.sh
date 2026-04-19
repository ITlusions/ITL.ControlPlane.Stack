#!/bin/sh
# Keycloak Setup Script - Matches setup-keycloak-realm.ps1
# Creates test realm with OAuth2 client and test user
#
# Environment variables:
#   KEYCLOAK_URL - Keycloak base URL (default: http://keycloak:8080)
#   KEYCLOAK_ADMIN - Admin username (default: admin)
#   KEYCLOAK_ADMIN_PASSWORD - Admin password (from keycloak/.env)
#   TEST_REALM_NAME - Name for test realm (default: test-realm)

set -e

# Defaults
KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
TEST_REALM_NAME="${TEST_REALM_NAME:-test-realm}"
TEST_USERNAME="testuser"
TEST_EMAIL="testuser@example.com"
TEST_PASSWORD="TestPassword123!"
CLIENT_ID="itl-test-client"

echo ""
echo "=========================================="
echo "ITL Keycloak Realm Setup"
echo "=========================================="
echo "Realm Name:   $TEST_REALM_NAME"
echo "Keycloak URL: $KEYCLOAK_URL"
echo ""

# Verify password is set
if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
    echo "ERROR: KEYCLOAK_ADMIN_PASSWORD not set"
    exit 1
fi

# Wait for Keycloak
echo "Step 1: Verifying Keycloak is ready..."
attempt=0
while [ $attempt -lt 30 ]; do
    if curl -sf "${KEYCLOAK_URL}/health/ready" > /dev/null 2>&1; then
        echo "[OK] Keycloak is ready!"
        break
    fi
    attempt=$((attempt + 1))
    sleep 2
done

if [ $attempt -eq 30 ]; then
    echo "ERROR: Keycloak not ready after 60 seconds"
    exit 1
fi

# ────────────────────────────────────────
# Step 2: Get Admin Token
# ────────────────────────────────────────
echo ""
echo "Step 2: Obtaining admin token..."

TOKEN_RESPONSE=$(curl -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password&client_id=admin-cli&username=${KEYCLOAK_ADMIN}&password=${KEYCLOAK_ADMIN_PASSWORD}" 2>&1) || {
    echo "ERROR: Failed to get admin token"
    exit 1
}

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Could not extract token"
    exit 1
fi
echo "[OK] Token obtained successfully"

# ────────────────────────────────────────
# Step 3: Create Service Client (master realm)
# ────────────────────────────────────────
echo ""
echo "Step 3: Creating service client 'itl-identity-service' in master realm..."

SERVICE_CLIENT_ID="itl-identity-service"

response=$(curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/master/clients" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -w "%{http_code}" \
    -o /dev/null \
    -d "{
        \"clientId\": \"${SERVICE_CLIENT_ID}\",
        \"name\": \"ITL Identity Service\",
        \"enabled\": true,
        \"publicClient\": false,
        \"serviceAccountsEnabled\": true,
        \"directAccessGrantsEnabled\": true,
        \"standardFlowEnabled\": false,
        \"redirectUris\": [\"http://localhost:*/*\"],
        \"webOrigins\": [\"*\"]
    }" 2>/dev/null || echo "error")

if [ "$response" = "201" ]; then
    echo "[OK] Service client created"
elif [ "$response" = "409" ]; then
    echo "[WARN] Service client already exists"
else
    echo "[WARN] Service client creation returned: $response"
fi

# Get service client UUID and secret
echo "Getting service client credentials..."
client_data=$(curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    "${KEYCLOAK_URL}/admin/realms/master/clients?clientId=${SERVICE_CLIENT_ID}" 2>/dev/null || echo "[]")

service_client_uuid=$(echo "$client_data" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

echo "[DEBUG] client_data: $client_data" | head -c 300
echo ""
echo "[DEBUG] extracted uuid: '$service_client_uuid'"

SERVICE_CLIENT_SECRET=""
if [ -n "$service_client_uuid" ]; then
    echo "  [OK] Found client UUID: $service_client_uuid"
    
    secret_data=$(curl -sf \
        -H "Authorization: Bearer $TOKEN" \
        "${KEYCLOAK_URL}/admin/realms/master/clients/${service_client_uuid}/client-secret" 2>/dev/null || echo "{}")
    
    # Extract secret using grep instead of sed for better JSON parsing
    SERVICE_CLIENT_SECRET=$(echo "$secret_data" | grep -o '"value":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$SERVICE_CLIENT_SECRET" ]; then
        echo "[OK] Service client secret obtained (${#SERVICE_CLIENT_SECRET} chars)"
    else
        echo "[DEBUG] Secret extraction failed"
        echo "[DEBUG] secret_data: $secret_data"
    fi
    
    # Assign admin roles to service account
    echo "Assigning admin roles to service account..."
    
    # Get service account user
    sa_user=$(curl -sf \
        -H "Authorization: Bearer $TOKEN" \
        "${KEYCLOAK_URL}/admin/realms/master/clients/${service_client_uuid}/service-account-user" 2>/dev/null || echo "{}")
    
    sa_user_id=$(echo "$sa_user" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$sa_user_id" ]; then
        # Get master-realm client (for admin roles)
        mgmt_data=$(curl -sf \
            -H "Authorization: Bearer $TOKEN" \
            "${KEYCLOAK_URL}/admin/realms/master/clients?clientId=master-realm" 2>/dev/null || echo "[]")
        
        mgmt_uuid=$(echo "$mgmt_data" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [ -n "$mgmt_uuid" ]; then
            # Get available roles
            roles=$(curl -sf \
                -H "Authorization: Bearer $TOKEN" \
                "${KEYCLOAK_URL}/admin/realms/master/clients/${mgmt_uuid}/roles" 2>/dev/null || echo "[]")
            
            for role_name in manage-users manage-clients manage-realm view-users view-clients view-realm; do
                role_id=$(echo "$roles" | grep -o "{[^}]*\"name\":\"${role_name}\"[^}]*}" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' || true)
                
                if [ -n "$role_id" ]; then
                    curl -sf -X POST \
                        "${KEYCLOAK_URL}/admin/realms/master/users/${sa_user_id}/role-mappings/clients/${mgmt_uuid}" \
                        -H "Authorization: Bearer $TOKEN" \
                        -H "Content-Type: application/json" \
                        -d "[{\"id\":\"${role_id}\",\"name\":\"${role_name}\"}]" 2>/dev/null || true
                fi
            done
            echo "[OK] Admin roles assigned"
        fi
    fi
else
    echo "[DEBUG] UUID extraction failed"
fi

# ────────────────────────────────────────
# Step 4: Create Test Realm
# ────────────────────────────────────────
echo ""
echo "Step 4: Creating realm '$TEST_REALM_NAME'..."

response=$(curl -sf -X POST "${KEYCLOAK_URL}/admin/realms" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -w "%{http_code}" \
    -o /dev/null \
    -d "{
        \"realm\": \"${TEST_REALM_NAME}\",
        \"displayName\": \"${TEST_REALM_NAME} (Test Realm)\",
        \"enabled\": true,
        \"sslRequired\": \"none\",
        \"bruteForceProtected\": false
    }" 2>/dev/null || echo "error")

if [ "$response" = "201" ] || [ "$response" = "204" ]; then
    echo "[OK] Realm '$TEST_REALM_NAME' created successfully"
elif [ "$response" = "409" ]; then
    echo "[WARN] Realm '$TEST_REALM_NAME' already exists"
else
    echo "[WARN] Realm creation returned: $response (may already exist)"
fi

# ────────────────────────────────────────
# Step 5: Get Realm ID
# ────────────────────────────────────────
echo ""
echo "Step 5: Getting realm ID..."

REALM_INFO=$(curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    "${KEYCLOAK_URL}/admin/realms/${TEST_REALM_NAME}" 2>/dev/null || echo "{}")

REALM_ID=$(echo "$REALM_INFO" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$REALM_ID" ]; then
    echo "[OK] Realm ID: $REALM_ID"
else
    echo "[WARN] Could not get realm ID"
fi

# ────────────────────────────────────────
# Step 6: Create Test User
# ────────────────────────────────────────
echo ""
echo "Step 6: Creating test user..."

response=$(curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/${TEST_REALM_NAME}/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -w "%{http_code}" \
    -o /dev/null \
    -d "{
        \"username\": \"${TEST_USERNAME}\",
        \"email\": \"${TEST_EMAIL}\",
        \"firstName\": \"Test\",
        \"lastName\": \"User\",
        \"enabled\": true,
        \"emailVerified\": true
    }" 2>/dev/null || echo "error")

if [ "$response" = "201" ]; then
    echo "[OK] Test user '$TEST_USERNAME' created"
    
    # Get user ID and set password
    user_data=$(curl -sf \
        -H "Authorization: Bearer $TOKEN" \
        "${KEYCLOAK_URL}/admin/realms/${TEST_REALM_NAME}/users?username=${TEST_USERNAME}")
    
    user_id=$(echo "$user_data" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$user_id" ]; then
        curl -sf -X PUT "${KEYCLOAK_URL}/admin/realms/${TEST_REALM_NAME}/users/${user_id}/reset-password" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"password\",\"value\":\"${TEST_PASSWORD}\",\"temporary\":false}" 2>/dev/null || true
        echo "[OK] Password set: $TEST_PASSWORD"
    fi
elif [ "$response" = "409" ]; then
    echo "[WARN] User '$TEST_USERNAME' already exists"
else
    echo "[WARN] User creation returned: $response"
fi

# ────────────────────────────────────────
# Step 7: Create Test Client
# ────────────────────────────────────────
echo ""
echo "Step 7: Creating test OAuth2 client..."

response=$(curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/${TEST_REALM_NAME}/clients" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -w "%{http_code}" \
    -o /dev/null \
    -d "{
        \"clientId\": \"${CLIENT_ID}\",
        \"name\": \"ITL Test Client\",
        \"enabled\": true,
        \"publicClient\": false,
        \"serviceAccountsEnabled\": true,
        \"directAccessGrantsEnabled\": true,
        \"standardFlowEnabled\": true,
        \"implicitFlowEnabled\": false,
        \"redirectUris\": [\"http://localhost:3000/*\", \"http://localhost:8080/*\"],
        \"webOrigins\": [\"*\"]
    }" 2>/dev/null || echo "error")

if [ "$response" = "201" ]; then
    echo "[OK] OAuth2 client '$CLIENT_ID' created"
elif [ "$response" = "409" ]; then
    echo "[WARN] Client '$CLIENT_ID' already exists"
else
    echo "[WARN] Client creation returned: $response"
fi

# ────────────────────────────────────────
# Step 8: Get Client Secret
# ────────────────────────────────────────
echo ""
echo "Step 8: Getting test client credentials..."

client_data=$(curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    "${KEYCLOAK_URL}/admin/realms/${TEST_REALM_NAME}/clients?clientId=${CLIENT_ID}" 2>/dev/null || echo "[]")

client_uuid=$(echo "$client_data" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

CLIENT_SECRET=""
if [ -n "$client_uuid" ]; then
    secret_data=$(curl -sf \
        -H "Authorization: Bearer $TOKEN" \
        "${KEYCLOAK_URL}/admin/realms/${TEST_REALM_NAME}/clients/${client_uuid}/client-secret" 2>/dev/null || echo "{}")
    
    CLIENT_SECRET=$(echo "$secret_data" | grep -o '"value":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$CLIENT_SECRET" ]; then
        echo "[OK] Client secret obtained"
    fi
fi

# ────────────────────────────────────────
# Step 9: Update .env with Secrets
# ────────────────────────────────────────
if [ -n "$SERVICE_CLIENT_SECRET" ]; then
    ENV_FILE="${ENV_FILE:-.env}"
    
    echo ""
    echo "Step 9: Updating .env with secrets..."
    
    # Update KEYCLOAK_CLIENT_SECRET in .env
    if [ -f "$ENV_FILE" ]; then
        if grep -q "^KEYCLOAK_CLIENT_SECRET=" "$ENV_FILE"; then
            sed -i.bak "s/^KEYCLOAK_CLIENT_SECRET=.*/KEYCLOAK_CLIENT_SECRET=$SERVICE_CLIENT_SECRET/" "$ENV_FILE"
            rm -f "$ENV_FILE.bak"
            echo "  [OK] Updated KEYCLOAK_CLIENT_SECRET in $ENV_FILE"
        else
            echo "KEYCLOAK_CLIENT_SECRET=$SERVICE_CLIENT_SECRET" >> "$ENV_FILE"
            echo "  [OK] Added KEYCLOAK_CLIENT_SECRET to $ENV_FILE"
        fi
    fi
else
    echo "[WARN] SERVICE_CLIENT_SECRET is empty - cannot update .env"
fi

# ────────────────────────────────────────
# Summary
# ────────────────────────────────────────
echo ""
echo "=========================================="
echo "Keycloak Setup Complete!"
echo "=========================================="
echo ""
echo "Service Client (for Identity Provider):"
echo "  Client ID:      $SERVICE_CLIENT_ID"
if [ -n "$SERVICE_CLIENT_SECRET" ]; then
    echo "  Client Secret:  $SERVICE_CLIENT_SECRET"
fi
echo "  Realm:          master"
echo ""
echo "Test Realm Configuration:"
echo "  Realm Name:     $TEST_REALM_NAME"
echo "  Realm ID:       $REALM_ID"
echo "  Keycloak URL:   $KEYCLOAK_URL"
echo ""
echo "Test User:"
echo "  Username:       $TEST_USERNAME"
echo "  Password:       $TEST_PASSWORD"
echo "  Email:          $TEST_EMAIL"
echo ""
echo "Test Client:"
echo "  Client ID:      $CLIENT_ID"
if [ -n "$CLIENT_SECRET" ]; then
    echo "  Client Secret:  $CLIENT_SECRET"
fi
echo ""
echo "=========================================="
echo ""
echo "To use with Identity Provider, set:"
echo "  KEYCLOAK_CLIENT_SECRET=$SERVICE_CLIENT_SECRET"
echo ""
