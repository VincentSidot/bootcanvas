# BootCanvas

Tiny x86 bootloader experiment that displays an image in VGA mode.

It runs on a 16-bit real mode CPU path and builds a raw boot image from two
assembly stages plus a converted `640x480`, 16-color image payload.

## Requirements

- `fasm`
- `qemu-system-i386`
- `uv`

## Build and Run

```sh
make build
make run
```

Generated files are written to `build/`.

## Change the Target Image

Put your image in the project, then update `IMAGE_SRC` in `Makefile`:

```make
IMAGE_SRC := image/my-picture.jpg
```

Then rebuild:

```sh
make clean
make build
```

The converter resizes the image to `640x480` and reduces it to 16 colors before
packing it into the boot image.
