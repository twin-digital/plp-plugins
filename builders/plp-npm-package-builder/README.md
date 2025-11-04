# NPM Package Builder

A builder plugin for creating distributable NPM package tarballs from Node.js projects.

## Features

- **NVM Integration**: Automatically installs and uses Node.js versions via NVM
- **Version Detection**: Reads Node.js version from `.nvmrc` or `package.json` engines
- **Corepack Support**: Uses Node.js Corepack for package manager management
- **Multi-Package Manager Support**: Works with npm, pnpm, and yarn (via Corepack)
- **Pre-installation**: Can pre-install common Node.js versions at build time
- **Dependency Installation**: Uses lockfiles for reproducible builds
- **Package Creation**: Creates standard `.tgz` tarball for distribution

## Requirements

Projects using this builder **must** specify the `packageManager` field in their `package.json`:

```json
{
  "packageManager": "pnpm@9.12.0"
}
```

This is the standard Corepack format. See [Node.js Corepack documentation](https://nodejs.org/api/corepack.html) for details.

## Build Arguments

| Argument                   | Description                                                               | Default   |
| -------------------------- | ------------------------------------------------------------------------- | --------- |
| `NVM_VERSION`              | Version of NVM to install                                                 | `0.40.3`  |
| `NODE_PREINSTALL_VERSIONS` | Comma-delimited list of Node versions to preinstall (e.g., `18,20,lts/*`) | `lts/jod` |

## Node.js Version Detection

The builder determines which Node.js version to use in the following order:

1. **`.nvmrc` file**: If present, uses the version specified
2. **`package.json` engines.node**: Reads from `engines.node` field
3. **Default**: Uses `lts/*` (latest LTS version)

Example `.nvmrc`:

```
20.11.0
```

Example `package.json`:

```json
{
  "engines": {
    "node": ">=20.0.0"
  }
}
```

## Package Manager Configuration

The builder uses **Corepack** (built into Node.js 16.9+) for package manager management. This ensures the exact package manager version specified in your project is used.

### Required Configuration

Your `package.json` **must** include a `packageManager` field:

```json
{
  "name": "my-package",
  "version": "1.0.0",
  "packageManager": "pnpm@9.12.0",
  "engines": {
    "node": ">=20.0.0"
  }
}
```

### Supported Package Managers

| Package Manager | Example Specification             | Notes                                           |
| --------------- | --------------------------------- | ----------------------------------------------- |
| npm             | `"packageManager": "npm@10.8.0"`  | Managed by Corepack                             |
| pnpm            | `"packageManager": "pnpm@9.12.0"` | Automatically installed via Corepack            |
| yarn            | `"packageManager": "yarn@4.0.2"`  | Supports both Yarn Classic (1.x) and Berry (2+) |

## Runtime Environment Variables

| Variable          | Description                                                 | Default      | Required |
| ----------------- | ----------------------------------------------------------- | ------------ | -------- |
| `PLP_SOURCE_PATH` | Absolute path to source code directory                      | `/source`    | No       |
| `PLP_BUILD_PATH`  | Absolute path to output directory for build artifacts       | `/build`     | No       |
| `PLP_CACHE_PATH`  | Absolute path to cache directory (persisted between builds) | `/tmp/cache` | No       |

### Cache Directory Usage

The `PLP_CACHE_PATH` is used to store package manager caches and stores:

- **npm**: `$PLP_CACHE_PATH/npm` - npm cache directory
- **pnpm**: `$PLP_CACHE_PATH/pnpm/store` - pnpm global store
- **yarn**: `$PLP_CACHE_PATH/yarn` - Yarn cache folder

Mounting a persistent volume at `PLP_CACHE_PATH` can significantly speed up builds by reusing cached packages.

## Directory Mounts

The builder uses the following directory paths (configurable via environment variables):

| Default Path | Environment Variable | Purpose                        | Mode                  |
| ------------ | -------------------- | ------------------------------ | --------------------- |
| `/source`    | `PLP_SOURCE_PATH`    | Source code directory          | Read-only recommended |
| `/build`     | `PLP_BUILD_PATH`     | Output directory for artifacts | Read-write            |
| `/tmp/cache` | `PLP_CACHE_PATH`     | Package manager cache          | Read-write            |

## Output

The builder creates a single tarball file in the build directory (`PLP_BUILD_PATH`):

```
{package-name}-{version}.tgz
```

Where:

- `{package-name}`: Sanitized package name from `package.json` (@ and / replaced with -)
- `{version}`: Package version from `package.json`

Example: `@myorg/my-package` version `1.2.3` becomes `myorg-my-package-1.2.3.tgz`

## Exit Codes

| Code | Meaning                                       |
| ---- | --------------------------------------------- |
| `0`  | Success                                       |
| `1`  | General error                                 |
| `3`  | Validation error (missing package.json, etc.) |
| `4`  | Missing required environment variable         |

## Usage Examples

### Basic Usage

Ensure your `package.json` has a `packageManager` field:

```json
{
  "name": "my-package",
  "version": "1.0.0",
  "packageManager": "pnpm@9.12.0"
}
```

Then build and run:

```bash
docker build -t plp-npm-package-builder .

docker run --rm \
  -v /path/to/source:/source:ro \
  -v /path/to/build:/build \
  -v /path/to/cache:/cache \
  -e PLP_SOURCE_PATH=/source \
  -e PLP_BUILD_PATH=/build \
  -e PLP_CACHE_PATH=/cache \
  plp-npm-package-builder
```

### With Pre-installed Node Versions and Caching

```bash
docker build \
  --build-arg NODE_PREINSTALL_VERSIONS="18,20,lts/*" \
  -t plp-npm-package-builder .

# First run - cache is empty
docker run --rm \
  -v /path/to/source:/source:ro \
  -v /path/to/build:/build \
  -v /path/to/cache:/cache \
  -e PLP_SOURCE_PATH=/source \
  -e PLP_BUILD_PATH=/build \
  -e PLP_CACHE_PATH=/cache \
  plp-npm-package-builder

# Subsequent runs - cache is reused (faster!)
docker run --rm \
  -v /path/to/source:/source:ro \
  -v /path/to/build:/build \
  -v /path/to/cache:/cache \
  -e PLP_SOURCE_PATH=/source \
  -e PLP_BUILD_PATH=/build \
  -e PLP_CACHE_PATH=/cache \
  plp-npm-package-builder
```

### GitHub Actions Integration

```yaml
- name: Build NPM package
  run: |
    docker run --rm \
      -v ${{ github.workspace }}:/source:ro \
      -v ${{ runner.temp }}/build:/build \
      -v ${{ runner.temp }}/cache:/cache \
      -e PLP_SOURCE_PATH=/source \
      -e PLP_BUILD_PATH=/build \
      -e PLP_CACHE_PATH=/cache \
      ghcr.io/twin-digital/plp-plugins/plp-npm-package-builder:latest
```

## Project Structure Requirements

### Minimum Requirements

```
my-package/
├── package.json        # Required
└── (source files)
```

### With Version Control

```
my-package/
├── package.json       # Required
├── .nvmrc             # Optional: Node.js version
├── pnpm-lock.yaml     # For pnpm projects
└── (source files)
```

### npm Project Example

```
my-package/
├── package.json        # Must include "packageManager": "npm@10.8.0"
├── package-lock.json
└── src/
    └── index.js
```

**package.json:**

```json
{
  "name": "my-npm-package",
  "packageManager": "npm@10.8.0",
  "engines": {
    "node": "20.x"
  }
}
```

### pnpm Project Example

```
my-package/
├── package.json        # Must include "packageManager": "pnpm@9.12.0"
├── pnpm-lock.yaml
├── .nvmrc             # Optional
└── src/
    └── index.ts
```

**package.json:**

```json
{
  "name": "my-pnpm-package",
  "packageManager": "pnpm@9.12.0",
  "engines": {
    "node": ">=20.0.0"
  }
}
```

### yarn Project Example

```
my-package/
├── package.json        # Must include "packageManager": "yarn@4.0.2"
├── yarn.lock
└── lib/
    └── index.js
```

**package.json:**

```json
{
  "name": "my-yarn-package",
  "packageManager": "yarn@4.0.2",
  "engines": {
    "node": "20"
  }
}
```

## Dependency Installation

The builder uses lockfile-based installation for reproducibility:

| Package Manager | Command                          |
| --------------- | -------------------------------- |
| npm             | `npm ci`                         |
| pnpm            | `pnpm install --frozen-lockfile` |
| yarn            | `yarn install --frozen-lockfile` |

This ensures builds are deterministic and match the lockfile exactly.

## Build Process

1. **Environment Validation**: Checks all required environment variables
2. **File Validation**: Ensures `package.json` exists
3. **Node.js Version Detection**: Reads from `.nvmrc` or `package.json`
4. **Node.js Installation**: Uses NVM to install/activate version
5. **Corepack Activation**: Enables Corepack for package manager management
6. **Package Manager Detection**: Reads `packageManager` from `package.json` (required)
7. **Package Manager Installation**: Corepack installs the specified version automatically
8. **Workspace Preparation**: Copies source to writable directory
9. **Dependency Installation**: Installs packages using lockfile
10. **Package Creation**: Creates tarball using package manager
11. **Artifact Move**: Moves tarball to build output directory with standardized name

## Troubleshooting

### "package.json not found"

Ensure the source directory is mounted correctly and contains a `package.json` file.

### "package.json must specify 'packageManager' field"

The builder requires a `packageManager` field in your `package.json`. Add it:

```json
{
  "packageManager": "pnpm@9.12.0"
}
```

You can set this automatically using Corepack:

```bash
# For pnpm
corepack use pnpm@9.12.0

# For yarn
corepack use yarn@4.0.2

# For npm
corepack use npm@10.8.0
```

### "Failed to create package tarball"

Check that:

- All dependencies are properly declared
- The package.json is valid
- The project builds successfully

### Native Module Build Failures

The builder includes build tools (python3, make, g++) for compiling native modules. If you encounter issues:

- Ensure your `package.json` specifies compatible versions
- Check that native dependencies support Alpine Linux

### Version Mismatch

If the wrong Node.js version is used:

- Add `.nvmrc` for explicit Node.js version
- Or specify in `package.json` engines field

## Security

- Runs as non-root user (`plp`)
- Source directory mounted read-only
- No network access required after dependencies are installed
- Uses official NVM installation method

## License

See the main repository LICENSE file.
