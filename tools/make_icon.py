#!/usr/bin/env python3
"""Bake a macOS-style app icon from the coach avatar: the image is fitted into
the standard 824 px squircle on a 1024 px transparent canvas, with the
continuous-curvature corners macOS uses, so it sits in the Dock like the
system's own icons. Pure Python (zlib), no Pillow needed.

  tools/make_icon.py assets/images/coach-avatar.png assets/images/app-icon.png
"""
import struct, sys, zlib

def load_png(path):
    data = open(path, 'rb').read(); pos = 8; idat = b''; w = h = 0; ctype = 0
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]; typ = data[pos+4:pos+8]; body = data[pos+8:pos+8+ln]; pos += 12 + ln
        if typ == b'IHDR': w, h, _bd, ctype = struct.unpack('>IIBB', body[:10])
        elif typ == b'IDAT': idat += body
    raw = zlib.decompress(idat); bpp = 4 if ctype == 6 else 3; stride = w * bpp
    rows = []; prev = bytearray(stride); i = 0
    for _y in range(h):
        f = raw[i]; i += 1; line = bytearray(raw[i:i+stride]); i += stride
        for x in range(stride):
            a = line[x-bpp] if x >= bpp else 0; b = prev[x]; c = prev[x-bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa = abs(p - a); pb = abs(p - b); pc = abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c); line[x] = (line[x] + pr) & 255
        rows.append(bytes(line)); prev = line
    return w, h, bpp, rows

def save_png(path, w, h, rows):
    raw = b''.join(b'\x00' + r for r in rows)
    def chunk(t, b): return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def squircle_alpha(u, v):
    # Apple's icon shape is close to a superellipse |x|^5 + |y|^5 = 1 in [-1, 1] coords.
    return 1.0 if (abs(u) ** 5 + abs(v) ** 5) <= 1.0 else 0.0

def main(src, dst):
    sw, sh, sbpp, srows = load_png(src)
    S = 1024; inner = 824; off = (S - inner) // 2
    out = []
    for y in range(S):
        row = bytearray(S * 4)
        for x in range(S):
            ix = x - off; iy = y - off
            if 0 <= ix < inner and 0 <= iy < inner:
                # 2x2 supersample of the mask for a soft edge.
                cover = 0.0
                for dy in (0.25, 0.75):
                    for dx in (0.25, 0.75):
                        u = ((ix + dx) / inner) * 2 - 1; v = ((iy + dy) / inner) * 2 - 1
                        cover += squircle_alpha(u, v)
                cover /= 4.0
                if cover > 0:
                    sx = min(sw - 1, int(ix * sw / inner)); sy = min(sh - 1, int(iy * sh / inner))
                    p = srows[sy][sx*sbpp:sx*sbpp+3]
                    row[x*4:x*4+4] = bytes([p[0], p[1], p[2], int(255 * cover)])
        out.append(bytes(row))
    save_png(dst, S, S, out)
    print("wrote", dst)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
