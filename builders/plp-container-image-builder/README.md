# Container Image Builder

A builder plugin for creating OCI-compliant container images using BuildKit in rootless, daemonless mode.

## Features

- **Rootless & Daemonless**: Uses BuildKit's rootless mode without requiring Docker daemon
- **OCI Compliance**: Outputs standard OCI image archives
- **BuildKit Caching**: Leverages layer caching for faster rebuilds
- **Flexible Paths**: Configurable source, build, and cache directories
- **Annotations**: Adds OCI image annotations for source, revision, and creation time

## Build Arguments

| Argument           | Description                | Default  |
| ------------------ | -------------------------- | -------- |
| `BUILDKIT_VERSION` | Version of BuildKit to use | `0.21.1` |

## Runtime Environment Variables

| Variable             | Description                                                  | Default      | Required |
| -------------------- | ------------------------------------------------------------ | ------------ | -------- |
| `PLP_SOURCE_PATH`    | Absolute path to source code directory containing Dockerfile | `/source`    | No       |
| `PLP_BUILD_PATH`     | Absolute path to output directory for build artifacts        | `/build`     | No       |
| `PLP_CACHE_PATH`     | Absolute path to cache directory (persisted between builds)  | `/tmp/cache` | No       |
| `GIT_REPOSITORY_URL` | Git repository URL (for OCI annotations)                     | _(empty)_    | No       |
| `GIT_SHA`            | Git commit SHA (for OCI annotations)                         | _(empty)_    | No       |

### Cache Directory Usage

The `PLP_CACHE_PATH` is used to store BuildKit layer cache:

- **BuildKit Cache**: `$PLP_CACHE_PATH/buildkit` - Layer cache for faster rebuilds

Mounting a persistent volume at `PLP_CACHE_PATH` can significantly speed up builds by reusing cached layers.

## Directory Mounts

The builder uses the following directory paths (configurable via environment variables):

| Default Path | Environment Variable | Purpose                                | Mode                  |
| ------------ | -------------------- | -------------------------------------- | --------------------- |
| `/source`    | `PLP_SOURCE_PATH`    | Source code directory with Dockerfile  | Read-only recommended |
| `/build`     | `PLP_BUILD_PATH`     | Output directory for OCI image archive | Read-write            |
| `/tmp/cache` | `PLP_CACHE_PATH`     | BuildKit cache directory               | Read-write            |

## Output

The builder creates a single OCI image archive in the build directory (`PLP_BUILD_PATH`):

```
container-image.tar
```

This is an OCI-compliant image archive that can be:

- Loaded into Docker: `docker load < container-image.tar`
- Pushed to registries with skopeo: `skopeo copy oci-archive:container-image.tar docker://...`
- Inspected with skopeo: `skopeo inspect oci-archive:container-image.tar`

## Exit Codes

| Code | Meaning                                                                   |
| ---- | ------------------------------------------------------------------------- |
| `0`  | Success                                                                   |
| `1`  | Build error (Dockerfile not found, build path not writable, build failed) |

## Usage Examples

### Basic Usage

Ensure your project has a `Dockerfile`:

```dockerfile
FROM alpine:3.20
RUN apk add --no-cache nodejs npm
COPY . /app
WORKDIR /app
CMD ["node", "index.js"]
```

Then build and run:

```bash
docker build -t plp-container-image-builder .

docker run --rm \
  --privileged \
  -v /path/to/source:/source:ro \
  -v /path/to/build:/build \
  -v /path/to/cache:/cache \
  -e PLP_SOURCE_PATH=/source \
  -e PLP_BUILD_PATH=/build \
  -e PLP_CACHE_PATH=/cache \
  plp-container-image-builder
```

**Note**: `--privileged` is required for BuildKit's rootless mode to function properly.

### With BuildKit Caching

```bash
# First run - cache is empty
docker run --rm \
  --privileged \
  -v /path/to/source:/source:ro \
  -v /path/to/build:/build \
  -v /path/to/cache:/cache \
  -e PLP_SOURCE_PATH=/source \
  -e PLP_BUILD_PATH=/build \
  -e PLP_CACHE_PATH=/cache \
  plp-container-image-builder

# Subsequent runs - cache is reused (much faster!)
docker run --rm \
  --privileged \
  -v /path/to/source:/source:ro \
  -v /path/to/build:/build \
  -v /path/to/cache:/cache \
  -e PLP_SOURCE_PATH=/source \
  -e PLP_BUILD_PATH=/build \
  -e PLP_CACHE_PATH=/cache \
  plp-container-image-builder
```

### With OCI Annotations

```bash
docker run --rm \
  --privileged \
  -v /path/to/source:/source:ro \
  -v /path/to/build:/build \
  -v /path/to/cache:/cache \
  -e PLP_SOURCE_PATH=/source \
  -e PLP_BUILD_PATH=/build \
  -e PLP_CACHE_PATH=/cache \
  -e GIT_REPOSITORY_URL=https://github.com/twin-digital/my-app \
  -e GIT_SHA=abc123def456 \
  plp-container-image-builder
```

The resulting image will have annotations:

- `org.opencontainers.image.source`: Git repository URL
- `org.opencontainers.image.revision`: Git commit SHA
- `org.opencontainers.image.created`: Build timestamp (UTC)

### GitHub Actions Integration

```yaml
- name: Build container image
  run: |
    docker run --rm \
      --privileged \
      -v ${{ github.workspace }}:/source:ro \
      -v ${{ runner.temp }}/build:/build \
      -v ${{ runner.temp }}/cache:/cache \
      -e PLP_SOURCE_PATH=/source \
      -e PLP_BUILD_PATH=/build \
      -e PLP_CACHE_PATH=/cache \
      -e GIT_REPOSITORY_URL=${{ github.server_url }}/${{ github.repository }} \
      -e GIT_SHA=${{ github.sha }} \
      ghcr.io/twin-digital/plp-plugins/plp-container-image-builder:latest
```

## Project Structure Requirements

### Minimum Requirements

```
my-app/
└── Dockerfile        # Required
```

### Typical Structure

```
my-app/
├── Dockerfile
├── .dockerignore    # Optional but recommended
└── src/
    └── (application files)
```

## BuildKit Features

This builder uses BuildKit which provides:

- **Multi-stage builds**: Efficient layering and smaller final images
- **Build secrets**: Secure handling of credentials during build
- **SSH forwarding**: Access private repositories during build
- **Cache mounts**: Fast dependency installation
- **Parallel builds**: Faster multi-stage builds

Example Dockerfile using BuildKit features:

```dockerfile
# syntax=docker/dockerfile:1

FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --only=production

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
CMD ["node", "index.js"]
```

## Build Process

1. **Environment Setup**: Sets default paths and creates cache directory
2. **Path Validation**: Displays configured paths
3. **File Validation**: Ensures Dockerfile exists at source path
4. **Write Validation**: Verifies build path is writable
5. **BuildKit Build**: Runs buildctl with:
   - Frontend: `dockerfile.v0`
   - Context: Source directory
   - Export cache: To cache directory
   - Import cache: From cache directory (if exists)
   - Output: OCI archive format
   - Annotations: Source, revision, created timestamp
6. **Artifact Output**: Saves `container-image.tar` to build directory

## Troubleshooting

### "Dockerfile not found"

Ensure the source directory contains a `Dockerfile` at the root level. If your Dockerfile has a different name or location, you'll need to modify the builder or use a symlink.

### "directory is not writable"

The build directory must be writable. Check:

- Volume mount permissions
- SELinux/AppArmor policies
- Directory ownership

### "operation not permitted" errors

The builder requires `--privileged` mode to run BuildKit's rootless mode. Ensure you're running with:

```bash
docker run --privileged ...
```

### Slow builds without caching

If builds are slow even after the first run:

- Ensure `PLP_CACHE_PATH` is mounted as a volume
- Verify the cache directory persists between runs
- Check that the cache mount has sufficient disk space

### BuildKit version issues

To use a different BuildKit version:

```bash
docker build \
  --build-arg BUILDKIT_VERSION=0.19.0 \
  -t plp-container-image-builder .
```

## Performance Tips

1. **Use .dockerignore**: Exclude unnecessary files from build context
2. **Enable Caching**: Always mount a persistent cache volume
3. **Multi-stage Builds**: Reduce final image size
4. **Cache Mounts**: Use `RUN --mount=type=cache` in Dockerfiles
5. **Layer Ordering**: Put frequently changing layers last

## Security

- **Rootless Mode**: BuildKit runs without root privileges inside the container
- **Privileged Container**: Required for BuildKit's rootless mode functionality
- **Read-only Source**: Source directory can be mounted read-only
- **No Network Access**: BuildKit can be configured for offline builds

## OCI Image Annotations

The builder automatically adds standard OCI annotations:

| Annotation                          | Source               | Example                                  |
| ----------------------------------- | -------------------- | ---------------------------------------- |
| `org.opencontainers.image.source`   | `GIT_REPOSITORY_URL` | `https://github.com/twin-digital/my-app` |
| `org.opencontainers.image.revision` | `GIT_SHA`            | `abc123def456`                           |
| `org.opencontainers.image.created`  | Current UTC time     | `2025-11-04T12:34:56Z`                   |

View annotations with:

```bash
skopeo inspect oci-archive:container-image.tar | jq '.annotations'
```

## Integration with Publishing

The OCI archive can be published using the `plp-container-image-publisher`:

```bash
# Build
docker run --rm --privileged \
  -v ./src:/source:ro \
  -v ./build:/build \
  plp-container-image-builder

# Publish
docker run --rm \
  -v ./build:/artifacts:ro \
  -e PLP_ARTIFACT_PATH=/artifacts/container-image.tar \
  -e PLP_IMAGE_REPOSITORY=ghcr.io/twin-digital/my-app \
  -e PLP_COMMIT_SHA=abc123 \
  -e PLP_REGISTRY_USERNAME=myuser \
  -e PLP_REGISTRY_PASSWORD=mytoken \
  plp-container-image-publisher
```

## License

See the main repository LICENSE file.
