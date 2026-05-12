# BootCanvas

Tiny x86 bootloader experiment that displays an image in VGA mode.

It runs on a 16-bit real mode CPU path and builds a raw boot image from two
assembly stages plus a converted `640x480`, 16-color image payload.

## Requirements

- `python3`
- `qemu-system-i386`
- `fasm` or Docker

## Build and Run

```sh
make build
make run
```

Generated files are written to `build/`.

Use `make python-setup` to create the local virtualenv and install Python
dependencies ahead of time. The build also invokes that setup path as needed.

`utils/fasm.sh` is the FASM entrypoint. It uses native `fasm` when available
and otherwise falls back to the Docker image built from `docker/Dockerfile` on
first use.

`utils/build.sh` and `utils/run.sh` remain as compatibility wrappers around the
Make targets.

## Change the Target Image

Put your image in the project, then pass it with `IMAGE_SRC`:

```sh
IMAGE_SRC=./image/my-picture.jpg make build
```

Then rebuild:

```sh
make clean
IMAGE_SRC=./image/my-picture.jpg make build
```

The converter resizes the image to `640x480` and reduces it to 16 colors before
packing it into the boot image.
