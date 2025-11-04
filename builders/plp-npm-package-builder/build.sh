#!/bin/bash
set -euo pipefail

# Load NVM
export NVM_DIR="/home/plp/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

echo "=========================================="
echo "NPM Package Builder"
echo "=========================================="
echo ""

# Set default paths if not provided
PLP_SOURCE_PATH="${PLP_SOURCE_PATH:-/source}"
PLP_BUILD_PATH="${PLP_BUILD_PATH:-/build}"
PLP_CACHE_PATH="${PLP_CACHE_PATH:-/tmp/cache}"

# Create cache directory if it doesn't exist
mkdir -p "$PLP_CACHE_PATH"

echo "Paths:"
echo "  Source: $PLP_SOURCE_PATH"
echo "  Build: $PLP_BUILD_PATH"
echo "  Cache: $PLP_CACHE_PATH"
echo ""

# Check for package.json
if [ ! -f "$PLP_SOURCE_PATH/package.json" ]; then
    echo "❌ Error: package.json not found in $PLP_SOURCE_PATH"
    exit 3
fi

echo "✅ Found package.json"
echo ""

# Determine Node.js version
echo "Determining Node.js version..."
NODE_VERSION=""

if [ -f "$PLP_SOURCE_PATH/.nvmrc" ]; then
    NODE_VERSION=$(cat "$PLP_SOURCE_PATH/.nvmrc" | tr -d '[:space:]')
    echo "  Found .nvmrc: $NODE_VERSION"
else
    # Try to read from package.json engines.node
    if command -v jq >/dev/null 2>&1; then
        ENGINES_NODE=$(jq -r '.engines.node // empty' "$PLP_SOURCE_PATH/package.json")
        if [ -n "$ENGINES_NODE" ]; then
            NODE_VERSION="$ENGINES_NODE"
            echo "  Found in package.json engines.node: $NODE_VERSION"
        fi
    fi
    
    # Default to LTS if nothing specified
    if [ -z "$NODE_VERSION" ]; then
        NODE_VERSION="lts/*"
        echo "  No version specified, using default: $NODE_VERSION"
    fi
fi

# Install and use the determined Node.js version
echo ""
echo "Installing Node.js version: $NODE_VERSION"
nvm install "$NODE_VERSION"
nvm use "$NODE_VERSION"

ACTUAL_NODE_VERSION=$(node --version)
echo "  ✅ Using Node.js $ACTUAL_NODE_VERSION"
echo "  npm version: $(npm --version)"
echo ""

# Enable Corepack (comes with Node.js 16.9+)
echo "Enabling Corepack..."
corepack enable
echo "  ✅ Corepack enabled"
echo ""

# Detect package manager from package.json
echo "Detecting package manager..."
PACKAGE_MANAGER_SPEC=$(jq -r '.packageManager // empty' "$PLP_SOURCE_PATH/package.json")

if [ -z "$PACKAGE_MANAGER_SPEC" ]; then
    echo "❌ Error: package.json must specify 'packageManager' field"
    echo "   Example: \"packageManager\": \"pnpm@9.12.0\""
    echo "   See: https://nodejs.org/api/corepack.html"
    exit 3
fi

echo "  Package manager specification: $PACKAGE_MANAGER_SPEC"

# Extract package manager name
PACKAGE_MANAGER=$(echo "$PACKAGE_MANAGER_SPEC" | cut -d'@' -f1)
echo "  Detected package manager: $PACKAGE_MANAGER"

# Corepack will automatically install the specified version
# We just need to verify it's available
corepack prepare "$PACKAGE_MANAGER_SPEC" --activate
echo "  ✅ Prepared $PACKAGE_MANAGER_SPEC via Corepack"
echo ""

# Set up package manager cache directories
echo "Configuring package manager cache..."
case "$PACKAGE_MANAGER" in
    pnpm)
        # pnpm uses a global store
        export PNPM_HOME="$PLP_CACHE_PATH/pnpm"
        export PNPM_STORE_PATH="$PLP_CACHE_PATH/pnpm/store"
        mkdir -p "$PNPM_HOME" "$PNPM_STORE_PATH"
        echo "  pnpm store: $PNPM_STORE_PATH"
        ;;
    yarn)
        # Yarn Berry (2+) uses .yarn/cache
        export YARN_CACHE_FOLDER="$PLP_CACHE_PATH/yarn"
        export YARN_GLOBAL_FOLDER="$PLP_CACHE_PATH/yarn/global"
        mkdir -p "$YARN_CACHE_FOLDER" "$YARN_GLOBAL_FOLDER"
        echo "  Yarn cache: $YARN_CACHE_FOLDER"
        ;;
    npm)
        # npm cache
        export NPM_CONFIG_CACHE="$PLP_CACHE_PATH/npm"
        mkdir -p "$NPM_CONFIG_CACHE"
        echo "  npm cache: $NPM_CONFIG_CACHE"
        ;;
esac
echo ""

# Copy source to a temporary working directory (since source may be read-only)
WORK_DIR="/tmp/build-workspace"
echo "Preparing workspace..."
cp -r "$PLP_SOURCE_PATH/." "$WORK_DIR/"
cd "$WORK_DIR"
echo "  ✅ Copied source to $WORK_DIR"
echo ""

# Install dependencies
echo "Installing dependencies..."
case "$PACKAGE_MANAGER" in
    pnpm)
        pnpm install --frozen-lockfile
        ;;
    yarn)
        yarn install --frozen-lockfile
        ;;
    npm)
        npm ci
        ;;
esac
echo "  ✅ Dependencies installed"
echo ""

# Pack the package
echo "Packing package..."
TARBALL=""
case "$PACKAGE_MANAGER" in
    pnpm)
        pnpm pack
        # pnpm pack creates a file with pattern: {name}-{version}.tgz
        TARBALL=$(ls -t *.tgz 2>/dev/null | head -n1)
        ;;
    yarn)
        # Yarn classic (1.x) vs berry (2+) have different pack commands
        YARN_VERSION=$(yarn --version)
        YARN_MAJOR=$(echo "$YARN_VERSION" | cut -d'.' -f1)
        if [ "$YARN_MAJOR" -ge 2 ]; then
            # Yarn 2+ (berry)
            yarn pack
            TARBALL=$(ls -t package.tgz 2>/dev/null | head -n1)
        else
            # Yarn 1.x (classic)
            yarn pack --filename package.tgz
            TARBALL="package.tgz"
        fi
        ;;
    npm)
        npm pack
        # npm pack creates a file with pattern: {name}-{version}.tgz
        TARBALL=$(ls -t *.tgz 2>/dev/null | head -n1)
        ;;
esac

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    echo "❌ Error: Failed to create package tarball"
    exit 1
fi

echo "  ✅ Created tarball: $TARBALL"
TARBALL_SIZE=$(du -h "$TARBALL" | cut -f1)
echo "  Size: $TARBALL_SIZE"
echo ""

# Move tarball to build directory with a standardized name
PACKAGE_NAME=$(jq -r '.name // "package"' "$PLP_SOURCE_PATH/package.json" | sed 's/@//g' | sed 's/\//-/g')
PACKAGE_VERSION=$(jq -r '.version // "0.0.0"' "$PLP_SOURCE_PATH/package.json")
OUTPUT_TARBALL="${PACKAGE_NAME}-${PACKAGE_VERSION}.tgz"

echo "Moving tarball to build directory..."
mv "$TARBALL" "$PLP_BUILD_PATH/$OUTPUT_TARBALL"
echo "  ✅ Saved to $PLP_BUILD_PATH/$OUTPUT_TARBALL"
echo ""

# Display final artifact info
echo "=========================================="
echo "Build Complete"
echo "=========================================="
echo "Artifact: $OUTPUT_TARBALL"
echo "Size: $TARBALL_SIZE"
echo "Node.js: $ACTUAL_NODE_VERSION"
echo "Package Manager: $PACKAGE_MANAGER_SPEC"
echo ""

ls -lh "$PLP_BUILD_PATH"
