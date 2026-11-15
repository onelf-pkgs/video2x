#!/bin/sh
# Tests the Video2X package build.sh wrote. Runs in the same container,
# right after it.
#
# The container has no GPU, so the processing itself cannot run here:
# the launches check that every library resolves, that the models are
# found, and that the program behaves like upstream's binary, not like
# a half-unpacked tree. A host with a Vulkan GPU runs a real upscale
# with the same file; the README describes it.
#
# Usage: test.sh
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)

xbps-install -Syu xbps > /dev/null
xbps-install -Syu > /dev/null
xbps-install -y curl ffmpeg > /dev/null

packed=dist/video2x-$arch.onelf
onelf verify "$packed"

# The payload is upstream's binary, the models and the shared
# libraries; the build artifacts upstream's AppImage also carried (pkg
# -config data, static archives, headers, Ubuntu's copyright files) and
# the recipe itself must not be in it.
list=$(onelf list "$packed")
for path in bin/video2x bin/models/realesrgan bin/models/rife \
    bin/models/realcugan bin/models/libplacebo \
    lib/libvideo2x.so lib/libavcodec.so.60
do
    case $list in
    *"$path"*) : ;;
    *)
        echo "the package is missing $path" >&2
        exit 1
        ;;
    esac
done
for path in lib/pkgconfig libncnn.a libglslang-default-resource-limits.a \
    usr/ include/ onelf.toml
do
    case $list in
    *"$path"*)
        echo "the package carries $path" >&2
        exit 1
        ;;
    esac
done

# Version, straight from upstream's payload.
"$packed" --version 2>&1 | grep -qx "Video2X version 6.4.0"

# A real run reaches the Vulkan stage: every library loaded and the
# models were found beside the binary. Without a GPU the processor
# cannot start, and that is the expected failure here; what must never
# appear is a missing library or a missing model file.
work_in=$(mktemp -u).mp4
log=$(mktemp)
ffmpeg -y -loglevel error -f lavfi -i testsrc2=size=160x90:rate=30:duration=2 \
    -pix_fmt yuv420p "$work_in"
if "$packed" -i "$work_in" -o "$work_in.out.mp4" -p realesrgan -d 0 -s 2 \
    --no-progress > "$log" 2>&1
then
    # A device showed up after all; the upscale must have produced
    # output dimensions twice the input's.
    ffprobe -v error -show_entries stream=width,height -of csv=p=0 \
        "$work_in.out.mp4" | grep -qx "320,180"
else
    if grep -q "loading shared libraries" "$log"; then
        cat "$log" >&2
        echo "a library did not resolve at launch" >&2
        exit 1
    fi
    if grep -qE "model param file not found|model bin file not found" "$log"; then
        cat "$log" >&2
        echo "the models beside the binary were not found" >&2
        exit 1
    fi
    grep -qiE "vulkan" "$log" || {
        cat "$log" >&2
        echo "the run failed before or without reaching the Vulkan stage" >&2
        exit 1
    }
fi
rm -f "$work_in" "$work_in.out.mp4" "$log"

echo "video2x-$arch: verify, contents and launch ok"
