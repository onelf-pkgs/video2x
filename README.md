# video2x

[Video2X](https://docs.video2x.org) packed for
[onelf](https://github.com/QaidVoid/onelf) packages. The application
is upstream's and its [README](https://github.com/k4yt3x/video2x)
describes it; this repository only repacks it into one file that runs
without FUSE and without the libraries upstream leaves to the host.

| | |
|---|---|
| Description | A machine learning-based video super resolution and frame interpolation framework |
| Upstream | <https://github.com/k4yt3x/video2x> |
| License | AGPL-3.0 |

## The repack

- Carries its own glibc family and every library the AppImage expects
  from the host, so it runs on musl hosts and old glibc ones.
- Models ship beside the binary, so their lookup always lands on the
  copies in the pack.
- Updates itself from this repository's releases; only updates signed
  with the key in `update.pub` are accepted once the control workflow
  commits one, unsigned until then.
- x86_64 only, like upstream's releases.

Every processor is Vulkan-only, so upscaling needs a Vulkan-capable
GPU; without one the run stops at the Vulkan stage, which the test
expects.

## Releases

Tagged `v<version>-<release>`; each release carries
`video2x-<arch>.onelf`. `test.sh` runs in the build container: it
verifies the file, checks the payload and runs realesrgan to the
Vulkan stage. On a GPU host the same file upscales for real, about 30
FPS on a 320x180 clip through a GTX 1060.
