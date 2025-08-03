# Build stage for compiling vips
FROM amazonlinux:2023 AS builder

# Install build dependencies
RUN dnf install -y \
    gcc gcc-c++ make meson ninja-build pkg-config \
    glib2-devel expat-devel libjpeg-turbo-devel \
    libpng-devel libtiff-devel libwebp-devel \
    wget tar xz && \
    dnf clean all

# Download and compile vips
WORKDIR /tmp
RUN wget https://github.com/libvips/libvips/releases/download/v8.15.1/vips-8.15.1.tar.xz && \
    tar xf vips-8.15.1.tar.xz && \
    cd vips-8.15.1 && \
    meson setup build --prefix=/usr/local --buildtype=release \
        -Dintrospection=disabled -Dmodules=disabled \
        -Dcplusplus=false -Ddeprecated=false && \
    cd build && \
    meson compile && \
    meson install

# Runtime stage
FROM ghcr.io/ql4b/lambda-shell-runtime:full

# Install runtime dependencies only
RUN microdnf install -y \
    glib2 expat libjpeg-turbo libpng libtiff libwebp && \
    microdnf clean all

# Create necessary directories
RUN mkdir -p /usr/local/lib/pkgconfig

# Copy vips binaries and libraries from builder
COPY --from=builder /usr/local/bin/vips* /usr/local/bin/
COPY --from=builder /usr/local/lib64/libvips* /usr/local/lib/
COPY --from=builder /usr/local/lib64/pkgconfig/vips* /usr/local/lib/pkgconfig/

# Set library path environment variable
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Copy custom runtime bootstrap
COPY runtime/bootstrap /var/runtime/bootstrap
RUN chmod +x /var/runtime/bootstrap

# Copy function code
COPY src/ /var/task/

# Set handler
CMD ["handler.thumb"]