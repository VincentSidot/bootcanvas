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
./utils/build.sh
./utils/run.sh
```

Generated files are written to `build/`.

If `fasm` is not available locally, the build falls back to the Docker wrapper
in `utils/fasm.sh`, which builds the local image from `docker/Dockerfile` on
first use.

`make build` and `make run` are still available as thin wrappers around those
scripts.

## Change the Target Image

Put your image in the project, then pass it with `IMAGE_SRC`:

```sh
IMAGE_SRC=./image/my-picture.jpg ./utils/build.sh
```

Then rebuild:

```sh
make clean
IMAGE_SRC=./image/my-picture.jpg ./utils/build.sh
```

The converter resizes the image to `640x480` and reduces it to 16 colors before
packing it into the boot image.
