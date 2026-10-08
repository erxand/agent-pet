"""Write an RGBA PNG with nothing but the standard library."""
import struct
import zlib

PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'
BIT_DEPTH = 8
COLOR_TYPE_RGBA = 6
NO_FILTER = b'\x00'


def chunk(chunk_type, data):
    """One PNG chunk: length, type, data, then the CRC of type and data."""
    crc = zlib.crc32(chunk_type + data) & 0xffffffff
    return struct.pack('>I', len(data)) + chunk_type + data + struct.pack('>I', crc)


def write(path, width, height, pixels):
    """Write pixels, a list of rows of (red, green, blue, alpha) tuples, to path."""
    scanlines = b''.join(
        NO_FILTER + bytes(channel for pixel in row for channel in pixel) for row in pixels
    )
    header = struct.pack('>IIBBBBB', width, height, BIT_DEPTH, COLOR_TYPE_RGBA, 0, 0, 0)
    with open(path, 'wb') as output:
        output.write(
            PNG_SIGNATURE
            + chunk(b'IHDR', header)
            + chunk(b'IDAT', zlib.compress(scanlines, 9))
            + chunk(b'IEND', b'')
        )
