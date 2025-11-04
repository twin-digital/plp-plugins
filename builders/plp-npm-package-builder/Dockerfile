FROM alpine:3.22

# Build arguments
ARG NVM_VERSION=0.40.3
ARG NODE_PREINSTALL_VERSIONS=lts/jod

# Needed to get correct binaries on alpine
# https://gist.github.com/ralexandr/8d991531360123dff9b9f72faaa0f0de
ENV NVM_NODEJS_ORG_MIRROR=https://unofficial-builds.nodejs.org/download/release

# Install base dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    jq \
    ca-certificates \
    # dependencies for using precompiled nodejs binaries on alpine
    libstdc++ \
    coreutils \
    # Dependencies for building native modules
    python3 \
    make \
    g++ \
    linux-headers

# Create non-root user
RUN addgroup -g 1000 plp && \
    adduser -D -u 1000 -G plp plp

# Switch to plp user for NVM installation
USER plp
WORKDIR /home/plp

# Install NVM
RUN curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash

# Set up environment for NVM
ENV NVM_DIR=/home/plp/.nvm

# Copy NVM architecture override for Alpine (musl) builds
RUN mkdir -p ~/.nvm/custom
COPY --chown=plp:plp nvm-arch-override.sh /home/plp/.nvm/custom/arch-override.sh

# Preinstall Node versions if specified
RUN if [ -n "$NODE_PREINSTALL_VERSIONS" ]; then \
        bash -c ". $NVM_DIR/nvm.sh && \
        . ~/.nvm/custom/arch-override.sh && \
        IFS=',' read -ra VERSIONS <<< \"$NODE_PREINSTALL_VERSIONS\" && \
        for VERSION in \"\${VERSIONS[@]}\"; do \
            echo \"Preinstalling Node.js version: \$VERSION\" && \
            nvm install \"\$VERSION\"; \
        done"; \
    fi

# Copy build script
COPY --chown=plp:plp build.sh /usr/local/bin/build.sh
RUN chmod +x /usr/local/bin/build.sh

# Set working directory
WORKDIR /source

# Default environment variables (can be overridden at runtime)
ENV PLP_SOURCE_PATH=/source
ENV PLP_BUILD_PATH=/build
ENV PLP_CACHE_PATH=/tmp/cache

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/build.sh"]
