#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 SuenMoney 应用图标（纯标准库，不依赖 PIL）。

画的是 BrandMark（docs R139）：机身 + 显示屏（带指示灯 + 内容条）+ 4×5 键盘，
亮键拼出 S。分层图标：
  background.png  —— 深色底板
  foreground.png  —— 透明底上的徽标本体
  startIcon.png   —— 两者合成（启动页用）
"""
import struct
import zlib
import os

SS = 4  # 超采样倍数（抗锯齿）

INK = (233, 238, 246)     # 机身（亮）
ACCENT = (0, 255, 136)    # 主题绿
SCREEN = (4, 23, 13)      # 显示屏底
KEY_OFF = (138, 143, 153)  # 未点亮的键
PLATE = (10, 10, 15)      # 底板

LIT_KEYS = [0, 1, 2, 5, 8, 9, 10, 13, 16, 17, 18]


def rounded_rect(px, size, x, y, w, h, r, color):
    """在 px（size*size 的 [(r,g,b,a)] 浮点缓冲）上填一个圆角矩形。"""
    x0, y0, x1, y1 = x, y, x + w, y + h
    r = max(0.0, min(r, w / 2, h / 2))
    for yy in range(int(y0), int(y1 + 0.999)):
        for xx in range(int(x0), int(x1 + 0.999)):
            if xx < 0 or yy < 0 or xx >= size or yy >= size:
                continue
            cx = min(max(xx + 0.5, x0 + r), x1 - r)
            cy = min(max(yy + 0.5, y0 + r), y1 - r)
            dx = xx + 0.5 - cx
            dy = yy + 0.5 - cy
            if dx * dx + dy * dy <= r * r + 1e-6:
                i = (yy * size + xx) * 4
                a = color[3]
                for k in range(3):
                    px[i + k] = px[i + k] * (1 - a) + color[k] * a
                px[i + 3] = min(1.0, px[i + 3] + a)


def circle(px, size, cx, cy, rad, color):
    for yy in range(int(cy - rad), int(cy + rad) + 1):
        for xx in range(int(cx - rad), int(cx + rad) + 1):
            if xx < 0 or yy < 0 or xx >= size or yy >= size:
                continue
            dx = xx + 0.5 - cx
            dy = yy + 0.5 - cy
            if dx * dx + dy * dy <= rad * rad:
                i = (yy * size + xx) * 4
                a = color[3]
                for k in range(3):
                    px[i + k] = px[i + k] * (1 - a) + color[k] * a
                px[i + 3] = min(1.0, px[i + 3] + a)


def draw_mark(px, size):
    """把 BrandMark 画在 size×size 缓冲的中心（占 ~62% 边长）。"""
    s = size * 0.62
    ox = (size - s) / 2
    oy = (size - s) / 2

    # 机身
    rounded_rect(px, size, ox, oy, s, s, s * 0.22, INK + (1.0,))

    pad = s * 0.08
    # 显示屏
    sx, sy = ox + pad, oy + pad
    sw, sh = s - pad * 2, s * 0.24
    rounded_rect(px, size, sx, sy, sw, sh, s * 0.06, SCREEN + (1.0,))
    # 指示灯 + 内容条
    circle(px, size, sx + s * 0.06 + s * 0.04, sy + sh / 2, s * 0.04, ACCENT + (1.0,))
    rounded_rect(px, size, sx + s * 0.06 + s * 0.12, sy + sh / 2 - s * 0.035,
                 s * 0.34, s * 0.07, s * 0.02, ACCENT + (1.0,))

    # 4×5 键盘
    ky = sy + sh + s * 0.06
    kg = s * 0.05
    kw = (sw - kg * 3) / 4
    kh = (oy + s - pad - ky - kg * 4) / 5
    idx = 0
    for r in range(5):
        for c in range(4):
            col = ACCENT if idx in LIT_KEYS else KEY_OFF
            rounded_rect(px, size, sx + c * (kw + kg), ky + r * (kh + kg),
                         kw, kh, min(kw, kh) * 0.18, col + (1.0,))
            idx += 1


def blank(size, color):
    return [c / 255.0 for c in color] * (size * size)


def write_png(path, px, size):
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter: none
        for x in range(size):
            i = (y * size + x) * 4
            r = int(max(0.0, min(1.0, px[i])) * 255 + 0.5)
            g = int(max(0.0, min(1.0, px[i + 1])) * 255 + 0.5)
            b = int(max(0.0, min(1.0, px[i + 2])) * 255 + 0.5)
            a = int(max(0.0, min(1.0, px[i + 3])) * 255 + 0.5)
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        out = struct.pack('>I', len(data)) + tag + data
        return out + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)
    return len(png)


def render(size, with_plate):
    big = size * SS
    px = blank(big, PLATE + (1.0,)) if with_plate else [0.0] * (big * big * 4)
    draw_mark(px, big)
    # 降采样
    out = [0.0] * (size * size * 4)
    for y in range(size):
        for x in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for dy in range(SS):
                for dx in range(SS):
                    i = ((y * SS + dy) * big + (x * SS + dx)) * 4
                    for k in range(4):
                        acc[k] += px[i + k]
            i = (y * size + x) * 4
            for k in range(4):
                out[i + k] = acc[k] / (SS * SS)
    return out


if __name__ == '__main__':
    SIZE = 1024
    targets = [
        '/home/suenmoney/hw-native/AppScope/resources/base/media',
        '/home/suenmoney/hw-native/entry/src/main/resources/base/media',
    ]
    bg = render(SIZE, True)
    fg = render(SIZE, False)
    for d in targets:
        os.makedirs(d, exist_ok=True)
        n1 = write_png(os.path.join(d, 'background.png'), bg, SIZE)
        n2 = write_png(os.path.join(d, 'foreground.png'), fg, SIZE)
        n3 = write_png(os.path.join(d, 'startIcon.png'), bg, SIZE)
        print(f'{d}: background={n1}B foreground={n2}B startIcon={n3}B')
