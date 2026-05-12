#!/usr/bin/env python3
# Convert an image to custom format

import argparse
import io

from PIL import Image


def parse_args():
    parser = argparse.ArgumentParser(description="Convert an image to custom format")
    parser.add_argument("input", help="Input image file")
    parser.add_argument("output", help="Output file")
    parser.add_argument(
        "--mode",
        "-m",
        choices=["encode", "decode"],
        default="encode",
        help="Mode of operation (default: encode)",
    )
    return parser.parse_args()


TARGET_SIZE = (640, 480)
HEADER_SIZE_BYTES = 2
PALETTE_SIZE_BYTES = 16 * 3
FILE_ALIGNMENT_BYTES = 512


def dump_palette(img, output_file):
    palette = img.getpalette()

    assert len(palette) == 16 * 3, "Palette should have 16 colors (48 values)"

    # Write as raw binary data => 0xRRGGBB
    for i in range(16):
        r = palette[i * 3]
        g = palette[i * 3 + 1]
        b = palette[i * 3 + 2]
        output_file.write(bytes([r, g, b]))


def dump_pixels(img, output_file):
    pixels = img.get_flattened_data()

    # Encode pixels as 4 bits per pixel (16 colors)
    # Use simple RLE encoding: if the next pixel is the same as the current one,
    # write a count byte followed by the pixel value byte. Otherwise, write the
    # pixel value byte directly.

    count = 1
    current_pixel = None

    for pixel in pixels:
        if pixel == current_pixel and count < 15:
            count += 1
        elif current_pixel is None:
            current_pixel = pixel
        else:
            byte = count << 4 | current_pixel & 0x0F
            output_file.write(bytes([byte]))
            current_pixel = pixel
            count = 1

    # Write the last pixel if it exists
    if current_pixel is not None:
        pixel = count << 4 | current_pixel & 0x0F
        output_file.write(bytes([pixel]))


def main():
    args = parse_args()

    if args.mode == "encode":
        encode(args.input, args.output)
    else:
        decode(args.input, args.output)


def encode(input: str, output: str):
    # Open the input image
    img = Image.open(input)

    # Resize the image
    img = img.resize(TARGET_SIZE)

    # Convert the image to 16 colors
    img = img.convert("P", palette=Image.ADAPTIVE, colors=16)

    payload = io.BytesIO()

    # Dump the palette
    dump_palette(img, payload)

    # Dump the pixel data
    dump_pixels(img, payload)

    payload_bytes = payload.getvalue()
    image_size_bytes = HEADER_SIZE_BYTES + len(payload_bytes)

    if image_size_bytes > 0xFFFF:
        raise ValueError(
            f"Encoded image is too large for u16 header: {image_size_bytes} bytes"
        )

    # Open the output file for writing
    with open(output, "wb") as output_file:
        output_file.write(image_size_bytes.to_bytes(HEADER_SIZE_BYTES, "little"))
        output_file.write(payload_bytes)
        padding_size_bytes = (-image_size_bytes) % FILE_ALIGNMENT_BYTES
        if padding_size_bytes:
            output_file.write(bytes(padding_size_bytes))

    return


def decode(input: str, output: str):
    palette = []
    with open(input, "rb") as input_file:
        image_size_bytes = int.from_bytes(input_file.read(HEADER_SIZE_BYTES), "little")
        file_size_bytes = input_file.seek(0, io.SEEK_END)

        if image_size_bytes > file_size_bytes:
            raise ValueError(
                f"Invalid image size header: expected at least {image_size_bytes} bytes, got {file_size_bytes}"
            )

        input_file.seek(HEADER_SIZE_BYTES)

        # Read the palette
        for _ in range(16):
            r = input_file.read(1)[0]
            g = input_file.read(1)[0]
            b = input_file.read(1)[0]
            palette.extend([r, g, b])

        # Read the pixel data
        pixels = []
        while True:
            if input_file.tell() >= image_size_bytes:
                break
            byte = input_file.read(1)
            if not byte:
                break
            pixel = byte[0]
            count = pixel >> 4
            value = pixel & 0x0F
            pixels.extend([value] * count)

    if len(palette) != PALETTE_SIZE_BYTES:
        raise ValueError(f"Invalid palette size: expected {PALETTE_SIZE_BYTES} bytes")

    # Create a new image with the palette and pixel data
    img = Image.new("P", TARGET_SIZE)
    img.putpalette(palette)
    img.putdata(pixels)

    # Save the image
    img.convert("RGB").save(output)


if __name__ == "__main__":
    main()
