#!/bin/bash
set -euo pipefail

# Script to exchange GitHub OIDC token for npm registry access token
# This is used for npm trusted publishing when publishing from CI/CD

# Required environment variables:
# - ACTIONS_ID_TOKEN_REQUEST_TOKEN: GitHub Actions OIDC token request token
# - ACTIONS_ID_TOKEN_REQUEST_URL: GitHub Actions OIDC token request URL

# Reauired parameters:
# - PACKAGE_NAME: The npm package name (will be URL-encoded)

if [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
  echo "❌ Error: ACTIONS_ID_TOKEN_REQUEST_TOKEN is not set" >&2
  exit 1
fi

if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  echo "❌ Error: ACTIONS_ID_TOKEN_REQUEST_URL is not set" >&2
  exit 1
fi

if [ -z "${1:-}" ]; then
  echo "❌ Error: Package name must be provided as first argument" >&2
  echo "Usage: $0 <package-name>" >&2
  exit 1
fi

PACKAGE_NAME="$1"

echo "Using npm trusted publishing (OIDC)..." >&2
echo "" >&2

# Step 1: Generate OIDC token from GitHub with npm audience
echo "Generating OIDC token..." >&2
OIDC_TOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=npm:registry.npmjs.org" | jq -r '.value')

if [ -z "$OIDC_TOKEN" ] || [ "$OIDC_TOKEN" = "null" ]; then
  echo "❌ Error: Failed to generate OIDC token" >&2
  exit 1
fi

echo "✅ OIDC token generated" >&2
echo "" >&2

# Step 2: Exchange OIDC token for npm registry access token
echo "Exchanging OIDC token for npm access token..." >&2

# URL-encode the package name (e.g., @scope/package -> %40scope%2Fpackage)
ENCODED_PACKAGE_NAME=$(printf '%s' "$PACKAGE_NAME" | jq -sRr @uri)

NPM_TOKEN_RESPONSE=$(curl -s -X POST "https://registry.npmjs.org/-/npm/v1/oidc/token/exchange/package/${ENCODED_PACKAGE_NAME}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${OIDC_TOKEN}")

NPM_REGISTRY_TOKEN=$(echo "$NPM_TOKEN_RESPONSE" | jq -r '.token // empty')

if [ -z "$NPM_REGISTRY_TOKEN" ]; then
  echo "❌ Error: Failed to exchange OIDC token for npm token" >&2
  echo "Response: $NPM_TOKEN_RESPONSE" >&2
  exit 1
fi

echo "✅ npm access token obtained" >&2
echo "" >&2

# Output the token to stdout (only thing on stdout)
echo "$NPM_REGISTRY_TOKEN"
