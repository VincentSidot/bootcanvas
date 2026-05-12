#!/usr/bin/env python3

# Convert an image to custom format
import argparse
import io
import math
import random

from PIL import Image


def parse_args():
    parser = argparse.ArgumentParser(description="Convert an image to custom format")
    parser.add_argument("input", help="Input image file")
    parser.add_argument("output", help="Output file")
    parser.add_argument(
        "--enable-palette-optimization",
        action="store_true",
        help="Optimize palette order for better RLE compression",
    )
    parser.add_argument(
        "--disable-rle", action="store_true", help="Disable RLE compression"
    )
    parser.add_argument(
        "--mode",
        "-m",
        choices=["encode", "decode"],
        default="encode",
        help="Mode of operation (default: encode)",
    )
    return parser.parse_args()


TARGET_SIZE = (640, 480)
PALETTE_SIZE_BYTES = 16 * 3
FILE_ALIGNMENT_BYTES = 512
MAGIC = b"CNVT"  # 4 bytes

# [MAGIC] <1bytes rle mode> <16 * 3 bytes palette> <plane 0 data> <plane 1 data> <plane 2 data> <plane 3 data>
# RLE mode: bitfield that indicates if a plane is compressed (1) or raw (0)


def bit_count(x):
    count = 0
    while x:
        count += x & 1
        x >>= 1
    return count


def hamming4(a, b):
    return bit_count(a ^ b)


def build_adjacency(img):
    w, h = img.size
    px = list(img.getdata())
    adj = [[0] * 16 for _ in range(16)]

    for y in range(h):
        row = y * w
        for x in range(w):
            a = px[row + x]

            if x + 1 < w:
                b = px[row + x + 1]
                adj[a][b] += 1
                adj[b][a] += 1

            if y + 1 < h:
                b = px[row + x + w]
                adj[a][b] += 1
                adj[b][a] += 1
    return adj


def permutation_cost(adj, perm):
    total = 0
    for a in range(16):
        for b in range(a + 1, 16):
            total += adj[a][b] * hamming4(perm[a], perm[b])
    return total


def optimize_palette_order(img, iterations=20_000):
    """
    Returns a new P image with palette and pixels remapped.

    The visual image is unchanged, but palette indices are reordered to make
    neighboring colors have similar binary indices.
    """
    adj = build_adjacency(img)

    perm = list(range(16))
    best = perm[:]
    current_cost = permutation_cost(adj, perm)
    best_cost = current_cost

    temperature = 1000.0  # initial temperature for simulated annealing

    for i in range(iterations):
        a, b = random.sample(range(16), 2)

        candidate = perm[:]
        candidate[a], candidate[b] = candidate[b], candidate[a]

        candidate_cost = permutation_cost(adj, candidate)
        delta = candidate_cost - current_cost

        if delta < 0 or random.random() < math.exp(-delta / temperature):
            perm = candidate
            current_cost = candidate_cost

            if current_cost < best_cost:
                best = perm[:]
                best_cost = current_cost

        temperature *= 0.9995  # cooling schedule

    return remap_palette_indices(img, best)


def remap_palette_indices(img, old_to_new):
    old_palette = img.getpalette()[: 16 * 3]

    new_palette = [0] * 16 * 3

    for old_index, new_index in enumerate(old_to_new):
        new_palette[new_index * 3 : new_index * 3 + 3] = old_palette[
            old_index * 3 : old_index * 3 + 3
        ]

    pixels = [old_to_new[p] for p in img.getdata()]

    out = Image.new("P", img.size)
    out.putpalette(new_palette)
    out.putdata(pixels)
    return out


class BitWriter:
    def __init__(self):
        self.__buffer = [0]
        self.current_bit = 0

    def write_bit(self, bit):
        if bit:
            self.__buffer[-1] |= 1 << (7 - self.current_bit)

        self.current_bit += 1

        if self.current_bit == 8:
            self.current_bit = 0
            self.__buffer.append(0)

    def pad_to_byte(self):
        if self.current_bit != 0:
            self.current_bit = 0
            self.__buffer.append(0)

    @property
    def buffer(self):
        assert self.current_bit == 0, "Buffer should be byte-aligned"
        # Last byte is incomplete by design, so we ignore it
        return self.__buffer[:-1]


def write_u16(file, value):
    assert 0 <= value <= 0xFFFF, "Value should fit in 16 bits"
    file.write(value.to_bytes(2, "little"))


def dump_palette(img, output_file):
    palette = img.getpalette()

    assert len(palette) == 16 * 3, "Palette should have 16 colors (48 values)"

    # Write as raw binary data => 0xRRGGBB
    for i in range(16):
        r = palette[i * 3]
        g = palette[i * 3 + 1]
        b = palette[i * 3 + 2]
        output_file.write(bytes([r, g, b]))


def rle_encode(data):
    assert len(data) > 0, "Data should not be empty"
    output = []
    current_value = data[0]
    count = 1
    for value in data[1:]:
        if value == current_value and count < 255:
            count += 1
        else:
            output.append(count)
            output.append(current_value)
            current_value = value
            count = 1
    output.append(count)
    output.append(current_value)

    output_len = len(output)

    return bytes(output), output_len


def write_data(data: bytes, output_file, disable_rle):
    data_len = len(data)
    encoded_data, encoded_len = rle_encode(data)

    if encoded_len > data_len or disable_rle:
        # Write raw data
        final_size = data_len
        final_data = data
        set_bit = False
    else:
        # Write RLE encoded data
        final_size = encoded_len
        final_data = encoded_data
        set_bit = True

    # Write the length of the encoded data
    write_u16(output_file, final_size)
    # Write the encoded data
    output_file.write(final_data)

    return set_bit, final_size


def get_plane_data(img):
    pixels = img.getdata()
    planes = [BitWriter() for _ in range(4)]

    for pixel in pixels:
        for i in range(4):
            planes[i].write_bit((pixel >> i) & 1)

    return [bytes(plane.buffer) for plane in planes]


def dump_pixels(img, output_file, disable_rle):
    compressed_size = 0
    raw_size = 0
    plane_data = get_plane_data(img)

    # rle_header = BitWriter()
    rle_mode = 0

    for i, plane in enumerate(plane_data):
        raw = len(plane)

        set_bit, compressed = write_data(plane, output_file, disable_rle)
        ratio = compressed / raw if raw > 0 else 1

        if set_bit:
            rle_mode |= 1 << i

        compressed_size += compressed
        raw_size += raw
        if set_bit:
            print(
                f"Plane {i}: {ratio * 100:.2f}% of original size ({compressed}/{raw} bytes)"
            )
        else:
            print(f"Plane {i}: raw data (no compression) ({raw} bytes)")

    ratio_global = compressed_size / raw_size if raw_size > 0 else 1
    print(
        f"Total compressed size: {ratio_global * 100:.2f}% of original size ({compressed_size}/{raw_size} bytes)"
    )

    return bytes([rle_mode])


def encode(input: str, output: str, optimize_palette=False, disable_rle=False):
    # Open the input image
    img = Image.open(input)

    # Resize the image
    img = img.resize(TARGET_SIZE)

    # Convert the image to 16 colors
    img = img.convert("P", palette=Image.Palette.ADAPTIVE, colors=16)

    if optimize_palette:
        # Optimize palette order to improve RLE compression
        img = optimize_palette_order(img)

    payload = io.BytesIO()

    # Dump the palette
    dump_palette(img, payload)

    # Dump the pixel data
    rle_header = dump_pixels(img, payload, disable_rle)
    assert len(rle_header) == 1, "RLE header should be 1 byte"

    payload_bytes = payload.getvalue()
    image_size_bytes = len(payload_bytes) + len(rle_header) + len(MAGIC)

    # Open the output file for writing
    with open(output, "wb") as output_file:
        output_file.write(MAGIC)
        output_file.write(rle_header)

        output_file.write(payload_bytes)
        padding_size_bytes = (-image_size_bytes) % FILE_ALIGNMENT_BYTES
        if padding_size_bytes:
            output_file.write(bytes(padding_size_bytes))

    print(
        f"Encoded image size: {image_size_bytes} bytes (including {padding_size_bytes} bytes of padding)"
    )

    return


def read_u16(file):
    return int.from_bytes(file.read(2), "little")


def rle_decode(data: bytes, expected_len: int):
    output = bytearray()

    if len(data) % 2 != 0:
        raise ValueError("Invalid RLE data length")

    for i in range(0, len(data), 2):
        count = data[i]
        value = data[i + 1]
        output.extend([value] * count)

        if len(output) > expected_len:
            raise ValueError("RLE decoded data is larger than expected")

    if len(output) != expected_len:
        raise ValueError(
            f"RLE decoded length mismatch: got {len(output)}, expected {expected_len}"
        )

    return bytes(output)


def decode(input: str, output: str):
    plane_size = (TARGET_SIZE[0] * TARGET_SIZE[1]) // 8
    num_pixels = TARGET_SIZE[0] * TARGET_SIZE[1]

    with open(input, "rb") as _file:
        magic = _file.read(4)
        if magic != MAGIC:
            raise ValueError(f"Invalid magic: {magic!r}")

        rle_mode = _file.read(1)[0]

        # Read palette: 16 colors, RGB triplets
        palette = list(_file.read(PALETTE_SIZE_BYTES))
        if len(palette) != PALETTE_SIZE_BYTES:
            raise ValueError("Unexpected end of file while reading palette")

        # PIL palettes are normally 256 colors, so pad the remaining entries.
        palette += [0] * (256 * 3 - len(palette))

        planes = []

        for plane_index in range(4):
            data_len = read_u16(_file)
            encoded_data = _file.read(data_len)

            if len(encoded_data) != data_len:
                raise ValueError(
                    f"Unexpected end of file while reading plane {plane_index}"
                )

            is_rle = (rle_mode >> plane_index) & 1

            if is_rle:
                plane = rle_decode(encoded_data, plane_size)
            else:
                plane = encoded_data
                if len(plane) != plane_size:
                    raise ValueError(
                        f"Raw plane {plane_index} has invalid size: "
                        f"{len(plane)} != {plane_size}"
                    )

            planes.append(plane)

    # Recombine 4 bitplanes into 4-bit palette indices.
    pixels = []

    for pixel_index in range(num_pixels):
        byte_index = pixel_index // 8
        bit_index = 7 - (pixel_index % 8)

        pixel = 0

        for plane_index in range(4):
            bit = (planes[plane_index][byte_index] >> bit_index) & 1
            pixel |= bit << plane_index

        pixels.append(pixel)

    img = Image.new("P", TARGET_SIZE)
    img.putpalette(palette)
    img.putdata(pixels)
    img.convert("RGB").save(output)


def main():
    args = parse_args()

    if args.enable_palette_optimization and args.disable_rle:
        args.enable_palette_optimization = False
        print(
            "Warning: Palette optimization is disabled when RLE is disabled, since it won't have any effect."
        )

    if args.mode == "encode":
        encode(
            args.input,
            args.output,
            optimize_palette=args.enable_palette_optimization,
            disable_rle=args.disable_rle,
        )
    else:
        if args.enable_palette_optimization:
            print(
                "Warning: Palette optimization has no effect in decode mode, since the palette order is determined by the input file."
            )
        if args.disable_rle:
            print(
                "Warning: RLE compression is determined by the input file, so --disable-rle has no effect in decode mode."
            )
        decode(args.input, args.output)


if __name__ == "__main__":
    main()
