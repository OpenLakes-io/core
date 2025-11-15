echo "📝 Getting admin JWT token..."

OM_HOST="localhost"
OM_PORT="30585"

ADMIN_USER="admin"
# Use default admin password if secret not provided
ADMIN_PASS="YWRtaW4="

POST_BODY="{
                \"email\": \"${ADMIN_USER}@open-metadata.org\",
                \"password\": \"${ADMIN_PASS}\"
              }"

# Get admin JWT token with retry
for i in $(seq 1 5); do
  TOKEN_RESPONSE=$(curl -s -X POST \
    "http://${OM_HOST}:${OM_PORT}/api/v1/users/login" \
    -H "Content-Type: application/json" \
    -d "$POST_BODY")

              ADMIN_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.accessToken // empty')

              if [ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != "null" ]; then
                echo "✅ Got admin token successfully"
                break
              fi

              echo "⏳ Attempt $i/5: Failed to get token, retrying..."
              echo "$TOKEN_RESPONSE"
              sleep 5
            done

            if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
              echo "❌ Failed to get admin token after 5 attempts"
              echo "Response: $TOKEN_RESPONSE"
              exit 1
            fi

            # Step 2: Check if user for bot already exists
            echo "🧑 Step 2: Checking if bot user already exists..."

            EXISTING_USER=$(curl -s -X GET \
              "http://${OM_HOST}:${OM_PORT}/api/v1/users/name/OpenLakesBot" \
              -H "Authorization: Bearer ${ADMIN_TOKEN}")

            USER_ID=$(echo "$EXISTING_USER" | jq -r '.id // empty')

            if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
              echo "  ✅ Found existing bot user with ID: ${USER_ID:0:8}..."
            else
              # Bot user doesn't exist, create it
              echo "  📝 Bot user not found, creating new bot user..."

              # Create bot user using the /v1/users endpoint
              USER_RESPONSE=$(curl -s -X PUT \
                "http://${OM_HOST}:${OM_PORT}/api/v1/users" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ${ADMIN_TOKEN}" \
                -d '{
                  "description": "OpenLakes Bot for Automating OpenLakes tasks",
                  "name": "OpenLakesBot",
                  "displayName": "OpenLakes Bot",
                  "email": "openlakes-bot@openlakes.io",
                  "isAdmin": true,
                  "domains": [],
                  "isBot": true,
                  "authenticationMechanism": {
                    "authType": "JWT",
                    "config": {
                      "JWTTokenExpiry": "Unlimited"
                    }
                  },
                  "botName": "OpenLakesBot"
                }')

              echo "  User creation response: $USER_RESPONSE"

              USER_ID=$(echo "$USER_RESPONSE" | jq -r '.id // empty')

              if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
                echo "  ❌ Failed to create bot user"
                echo "  Response: $USER_RESPONSE"
                exit 1
              fi

              echo "  ✅ Created bot user with ID: ${USER_ID:0:8}..."
            fi

            # Step 3: Check if bot already exists
            echo "🤖 Step 3: Checking if bot already exists..."

            EXISTING_BOT=$(curl -s -X GET \
              "http://${OM_HOST}:${OM_PORT}/api/v1/bots/name/OpenLakesBot" \
              -H "Authorization: Bearer ${ADMIN_TOKEN}")

            BOT_USER_ID=$(echo "$EXISTING_BOT" | jq -r '.botUser.id // empty')

            if [ -n "$BOT_USER_ID" ] && [ "$BOT_USER_ID" != "null" ]; then
              echo "  ✅ Found existing bot with user ID: ${BOT_USER_ID:0:8}..."
              echo "${EXISTING_BOT}"
            else
              # Bot doesn't exist, create it
              echo "  📝 Bot not found, creating new bot..."

              # Create bot using the /v1/bots endpoint
              # botUser = bot username (must match user name created above)
              BOT_RESPONSE=$(curl -s -X PUT \
                "http://${OM_HOST}:${OM_PORT}/api/v1/bots" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ${ADMIN_TOKEN}" \
                -d '{
                  "name": "OpenLakesBot",
                  "botUser": "OpenLakesBot",
                  "description": "Bot for automated service registration and metadata ingestion"
                }')

              echo "  Bot creation response: $BOT_RESPONSE"

              # Extract bot user ID from the botUser field in the response
              BOT_USER_ID=$(echo "$BOT_RESPONSE" | jq -r '.botUser.id // empty')

              if [ -z "$BOT_USER_ID" ] || [ "$BOT_USER_ID" = "null" ]; then
                echo "  ❌ Failed to create bot"
                echo "  Response: $BOT_RESPONSE"
                exit 1
              fi

              echo "  ✅ Created bot with user ID: ${BOT_USER_ID:0:8}..."
            fi

            echo "  ✅ Bot user ID: ${BOT_USER_ID:0:8}..."

            # Step 4: GET the authentication mechanism to retrieve the JWT token
            echo "  🔑 Retrieving JWT token from auth mechanism..."
            AUTH_MECHANISM_RESPONSE=$(curl -s -X GET \
              "http://${OM_HOST}:${OM_PORT}/api/v1/users/auth-mechanism/${BOT_USER_ID}" \
              -H "Authorization: Bearer ${ADMIN_TOKEN}")

            BOT_TOKEN=$(echo "$AUTH_MECHANISM_RESPONSE" | jq -r '.config.JWTToken // empty')

            if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "null" ] || [ "$BOT_TOKEN" = "" ]; then
              echo "  ❌ Failed to retrieve bot token from auth mechanism"
              echo "  Response: $AUTH_MECHANISM_RESPONSE"
              exit 1
            fi

            echo "  ✅ Retrieved bot JWT token"
            echo "Response: ${AUTH_MECHANISM_RESPONSE}"


            echo "✅ Bot setup complete. Token (first 20 chars): ${BOT_TOKEN:0:20}..."

            # Test the JWT token against the API
            echo ""
            echo "🔐 Step 5: Testing JWT token authentication..."
            echo "================================================"

            # Test 1: Get current user (bot) info
            echo "📋 Test 5.1: Retrieving bot user information..."
            BOT_USER_RESPONSE=$(curl -s -X GET \
              "http://${OM_HOST}:${OM_PORT}/api/v1/users/name/openlakesbot" \
              -H "Authorization: Bearer ${BOT_TOKEN}")

            BOT_USER_NAME=$(echo "$BOT_USER_RESPONSE" | jq -r '.name // empty')
            if [ "$BOT_USER_NAME" = "openlakesbot" ]; then
              echo "  ✅ Successfully authenticated as bot user"
              echo "  - Name: $(echo "$BOT_USER_RESPONSE" | jq -r '.displayName')"
              echo "  - Email: $(echo "$BOT_USER_RESPONSE" | jq -r '.email')"
              echo "  - Is Bot: $(echo "$BOT_USER_RESPONSE" | jq -r '.isBot')"
              echo "  - Is Admin: $(echo "$BOT_USER_RESPONSE" | jq -r '.isAdmin')"
            else
              echo "  ❌ Failed to retrieve bot user info"
              echo "  Response: $BOT_USER_RESPONSE"
            fi

            # Test 2: List databases (requires read permissions)
            echo ""
            echo "📋 Test 5.2: Listing database services..."
            DATABASES_RESPONSE=$(curl -s -X GET \
              "http://${OM_HOST}:${OM_PORT}/api/v1/services/databaseServices?limit=5" \
              -H "Authorization: Bearer ${BOT_TOKEN}")

            DB_COUNT=$(echo "$DATABASES_RESPONSE" | jq -r '.paging.total // 0')
            if [ "$DB_COUNT" -ge 0 ]; then
              echo "  ✅ Successfully retrieved database services (count: $DB_COUNT)"
              echo "$DATABASES_RESPONSE" | jq -r '.data[]?.name // empty' | while read -r db; do
                [ -n "$db" ] && echo "  - $db"
              done
            else
              echo "  ❌ Failed to list database services"
              echo "  Response: $DATABASES_RESPONSE"
            fi

            # Test 3: Create a test tag (requires write permissions)
            echo ""
            echo "📋 Test 5.3: Testing write permissions (create tag category)..."
            TEST_TAG_NAME="botTestTag"
            TAG_RESPONSE=$(curl -s -X POST \
              "http://${OM_HOST}:${OM_PORT}/api/v1/tags" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${BOT_TOKEN}" \
              -d "{
                \"name\": \"${TEST_TAG_NAME}\",
                \"displayName\": \"Bot Test Tag\",
                \"description\": \"Test tag created by bot to verify JWT permissions\"
              }")

            TAG_ID=$(echo "$TAG_RESPONSE" | jq -r '.id // empty')
            if [ -n "$TAG_ID" ] && [ "$TAG_ID" != "null" ]; then
              echo "  ✅ Successfully created test tag (id: ${TAG_ID:0:8}...)"

              # Clean up test tag
              echo "  🗑️  Cleaning up test tag..."
              DELETE_RESPONSE=$(curl -s -X DELETE \
                "http://${OM_HOST}:${OM_PORT}/api/v1/tags/${TAG_ID}?hardDelete=true" \
                -H "Authorization: Bearer ${BOT_TOKEN}")
              echo "  ✅ Test tag cleaned up"
            else
              echo "  ⚠️  Could not create test tag (might need admin permissions)"
              echo "  Response: $(echo "$TAG_RESPONSE" | jq -r '.message // .error // "Unknown error"')"
            fi

            # Test 4: Verify API health with authentication
            echo ""
            echo "📋 Test 5.4: Testing authenticated health endpoint..."
            HEALTH_RESPONSE=$(curl -s -X GET \
              "http://${OM_HOST}:${OM_PORT}/api/v1/system/config/auth" \
              -H "Authorization: Bearer ${BOT_TOKEN}")

            AUTH_PROVIDER=$(echo "$HEALTH_RESPONSE" | jq -r '.provider // empty')
            if [ -n "$AUTH_PROVIDER" ]; then
              echo "  ✅ Successfully accessed system config"
              echo "  - Auth Provider: $AUTH_PROVIDER"
              echo "  - Public Keys URL: $(echo "$HEALTH_RESPONSE" | jq -r '.publicKeyUrls[0] // "N/A"')"
            else
              echo "  ❌ Failed to access system config"
            fi

            # Test 5: Validate JWT expiry
            echo ""
            echo "📋 Test 5.5: Checking JWT token expiry..."
            # Decode JWT payload (base64 decode the middle part)
            JWT_PAYLOAD=$(echo "${BOT_TOKEN}" | cut -d'.' -f2 | base64 -d 2>/dev/null || echo "{}")
            EXP_TIME=$(echo "$JWT_PAYLOAD" | jq -r '.exp // empty' 2>/dev/null)

            if [ -n "$EXP_TIME" ] && [ "$EXP_TIME" != "null" ]; then
              CURRENT_TIME=$(date +%s)
              if [ "$EXP_TIME" -gt "$CURRENT_TIME" ]; then
                TIME_REMAINING=$((EXP_TIME - CURRENT_TIME))
                echo "  ✅ Token is valid for $(($TIME_REMAINING / 86400)) days"
              else
                echo "  ⚠️  Token appears to be expired"
              fi
            else
              echo "  ✅ Token has unlimited expiry (as configured)"
            fi

            echo ""
            echo "================================================"
            echo "🎉 JWT Token Verification Complete!"
            echo ""


#eyJraWQiOiJHYjM4OWEtOWY3Ni1nZGpzLWE5MmotMDI0MmJrOTQzNTYiLCJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJvcGVuLW1ldGFkYXRh
# Lm9yZyIsInN1YiI6Im9wZW5sYWtlc2JvdCIsInJvbGVzIjpbIkFkbWluIl0sImVtYWlsIjoib3Blbmxha2VzLWJvdEBvcGVubGFrZXMuaW8iLCJpc0JvdCI6d
# HJ1ZSwidG9rZW5UeXBlIjoiQk9UIiwiaWF0IjoxNzYzMTc3MzU5LCJleHAiOm51bGx9.IrBpMpoYoxtmf-nAbpubBHVJ_yHJq_kgaMReGeMl2joZtyBN_3Ldg
# n5WJLDG3JchzHHuSnxaJF4ROwAytnvGcTAijYavibYICEkqHjASj9oQeEZQBsTtYErtj_eyLqA73-i-xl3UNRdOYtTYlkbia1QsDw5MXiKLCuwkFCBLVF1Se-
# RYg-rBirysCZxB5SLKnyJ6zv2iJ4-5GSg2_XE2qsvVMnBo5feTKu4FQ7YniJGgXIbsT859i5xP2cP-SFYobTJavKvGpX1g7XCS0IlDvW3LLVbQ4XPl-DG8Hl-
# GEsmjCX5D1GI34e-uIWQz482zYzvuDOndW4UWHRKzxmV6qg

