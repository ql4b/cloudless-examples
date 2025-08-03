# Build stage - compile vips
FROM ghcr.io/ql4b/lambda-shell-runtime:full AS builder

RUN dnf update -y && \
    dnf install -y xz tar gcc gcc-c++ ninja-build python3-pip pkgconfig \
        glib2-devel libpng-devel libjpeg-turbo-devel expat-devel && \
    pip3 install meson && \
    # Download and compile vips
    cd /tmp && \
    curl -L https://github.com/libvips/libvips/releases/download/v8.15.2/vips-8.15.2.tar.xz -o vips.tar.xz && \
    tar xf vips.tar.xz && \
    cd vips-8.15.2 && \
    meson setup build --prefix=/usr --default-library=shared \
        -Dmagick=disabled -Dfftw=disabled -Dopenexr=disabled \
        -Dcfitsio=disabled -Dwebp=disabled -Dopenslide=disabled && \
    cd build && \
    meson compile && \
    meson install

# Runtime stage - minimal final image
FROM ghcr.io/ql4b/lambda-shell-runtime:full

# Copy only the compiled binaries and libraries
COPY --from=builder /usr/bin/vipsthumbnail /usr/bin/
COPY --from=builder /usr/lib64/libvips* /usr/lib/
COPY --from=builder /usr/lib64/pkgconfig/vips* /usr/lib64/pkgconfig/

# Install minimal runtime dependencies
RUN dnf install -y glib2 libpng libjpeg-turbo expat && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Copy function code
COPY src/ /var/task/
COPY runtime/ /var/runtime/

# Test installation
RUN /usr/bin/vipsthumbnail --version