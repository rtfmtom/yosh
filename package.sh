#!/bin/bash
#
# Package yosh + Fil-C runtime into a self-contained archive for deployment.
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "Packaging yosh for deployment..."

mkdir -p "$STAGING_DIR/opt/fil/lib"

# Copy the yosh binary
cp "$SCRIPT_DIR/prefix/bin/yosh" "$STAGING_DIR/yosh"

# Fil-C runtime core
for lib in ld-yolo-x86_64.so libc.so.6666 libm.so.6666 libpizlo.so libyolocimpl.so libyolomimpl.so; do
    cp "/opt/fil/lib/$lib" "$STAGING_DIR/opt/fil/lib/"
done

# Fil-C compiled libraries (real files)
for lib in libncursesw.so.6.5 libcurl.so.4.8.0 libssl.so.3 libcrypto.so.3 \
           libnghttp2.so.14.28.1 libidn2.so.0.4.0 libzstd.so.1.5.6 \
           libz.so.1.3.1 libunistring.so.5.1.0; do
    cp "/opt/fil/lib/$lib" "$STAGING_DIR/opt/fil/lib/"
done

# Symlinks
cd "$STAGING_DIR/opt/fil/lib"
ln -s libncursesw.so.6.5    libncursesw.so.6
ln -s libcurl.so.4.8.0      libcurl.so.4
ln -s libnghttp2.so.14.28.1 libnghttp2.so.14
ln -s libidn2.so.0.4.0      libidn2.so.0
ln -s libzstd.so.1.5.6      libzstd.so.1
ln -s libz.so.1.3.1         libz.so.1
ln -s libunistring.so.5.1.0 libunistring.so.5

# Create the archive
OUTPUT="$SCRIPT_DIR/yosh-debian12-x86_64.tar.gz"
cd "$STAGING_DIR"
tar czf "$OUTPUT" yosh opt/

echo "Created: $OUTPUT"
echo "Size: $(du -sh "$OUTPUT" | cut -f1)"
