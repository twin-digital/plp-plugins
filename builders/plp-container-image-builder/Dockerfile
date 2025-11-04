ARG BUILDKIT_VERSION=0.21.1
FROM moby/buildkit:v${BUILDKIT_VERSION} AS buildkit

VOLUME /build
VOLUME /source

# Create required directories
RUN mkdir -p /source /build && chown 1000:1000 /source && chown 1000:1000 /build

# Copy the build script
COPY build.sh /usr/local/bin/build.sh
RUN chmod +x /usr/local/bin/build.sh

# Default environment variables (can be overridden at runtime)
ENV PLP_SOURCE_PATH=/source
ENV PLP_BUILD_PATH=/build
ENV PLP_CACHE_PATH=/tmp/cache

# Set the entrypoint to the build script
ENTRYPOINT ["/usr/local/bin/build.sh"]
