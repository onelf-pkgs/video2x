#!/bin/sh
# Builds Video2X for this machine's architecture into dist/:
#
#   video2x-<arch>.onelf
#
# Nothing is compiled: upstream's AppImage already carries the binary,
# every library it links against, and the model files, and the recipe
# assembles them into one tree. The bundle updates itself from the
# latest release, accepting only updates signed with update.pub when the
# repository has one, and unsigned ones until then.
#
# Usage: build.sh
#
# Runs as root in a Void Linux (glibc) container with this directory as
# the working directory and onelf on PATH.
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)
[ "$arch" = x86_64 ] || {
    echo "upstream publishes this release only for x86_64, not $arch" >&2
    exit 1
}

# toml <table> <key>: the string value of <key> in [<table>] of
# package.toml.
toml() {
    awk -v table="[$1]" -v key="$2" '
        /^\[/ { in_table = ($0 == table); next }
        in_table && $1 == key && $2 == "=" { gsub(/"/, "", $3); print $3; exit }
    ' package.toml
}

version=$(toml sources.video2x version)
release=$(sed -n 's/^release = //p' package.toml)

# The runtime installs only a strictly newer revision, so a client is
# never rolled back: 6.4.0 release 2 is 6004000002. awk reads Ventoy's
# zero-padded parts, such as the 05 of 1.1.05, as decimal.
revision=$(echo "$version.$release" | awk -F. '
    NF != 4 { exit 1 }
    { for (i = 2; i <= 4; i++) if ($i >= 1000) exit 1 }
    { printf "%.0f", $1 * 1e9 + $2 * 1e6 + $3 * 1e3 + $4 }
') || {
    echo "version $version release $release does not fit an update revision" >&2
    exit 1
}
if [ -f update.pub ]; then
    trust="key = \"$PWD/update.pub\""
else
    trust="unsigned = true"
fi

xbps-install -Syu xbps > /dev/null
xbps-install -Syu > /dev/null
xbps-install -y curl file findutils > /dev/null
# Upstream's AppImage leans on the host for a few libraries it does not
# carry (the Vulkan loader and parts of X11 among them); the container
# supplies them so the bundle does not have to trust the host.
xbps-install -y vulkan-loader libX11 libxcb libgpg-error harfbuzz \
    alsa-lib mit-krb5-libs e2fsprogs-libs libdrm fribidi > /dev/null

work=$PWD/build/work
file=build/src/Video2X-x86_64.AppImage
if [ ! -f "$file" ]; then
    mkdir -p build/src
    url=$(toml sources.video2x url | sed "s/{version}/$version/")
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
fi
echo "$(toml sources.video2x sha256)  $file" | sha256sum -c - > /dev/null

rm -rf "$work"
mkdir -p "$work"
chmod +x "$file"
# --appimage-extract reads the squashfs payload without FUSE; the
# runtime needs only the container's glibc to do it.
cd "$work" && "$OLDPWD/$file" --appimage-extract > /dev/null
cd "$OLDPWD"

payload=$work/squashfs-root/usr
tree=$work/video2x
mkdir -p "$tree/bin" "$tree/lib"

# The binary sits in bin/ with the models beside it: the program
# searches its own directory for them last, and a packed tree never
# changes, so the lookup always lands there.
cp "$payload/bin/video2x" "$tree/bin/video2x"
cp -r "$payload/share/video2x/models" "$tree/bin/models"

# Every library the program links against comes from upstream; only
# static archives and pkg-config data, which nothing loads at runtime,
# are dropped.
cp "$payload"/lib/*.so* "$tree/lib/"
find "$tree/lib" -name '*.a' -delete
rm -rf "$tree/lib/pkgconfig"

for needed in \
    "$tree/bin/video2x" \
    "$tree/bin/models/realesrgan" \
    "$tree/bin/models/rife" \
    "$tree/bin/models/realcugan" \
    "$tree/bin/models/libplacebo" \
    "$tree/lib/libvideo2x.so" \
    "$tree/lib/libavcodec.so.60"
do
    [ -e "$needed" ] || {
        echo "the tree is missing $needed" >&2
        exit 1
    }
done

# The recipe is checked in beside this script; its placeholders expand
# from this environment when onelf loads it. The update section names
# this architecture's asset, so it is added here.
export VIDEO2X_VERSION=$version
cp onelf.toml "$tree/onelf.toml"
cat >> "$tree/onelf.toml" <<EOF

[update]
url = "https://github.com/onelf-pkgs/video2x/releases/latest/download/video2x-$arch.onelf"
revision = $revision
$trust
EOF

mkdir -p dist
onelf build "$tree" -o "dist/video2x-$arch.onelf"

ls -l dist
