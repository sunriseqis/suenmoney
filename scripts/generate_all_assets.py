#!/usr/bin/env python3
import os
import re
import math
import base64
from PIL import Image, ImageDraw

ROOT_DIR = "/home/suenmoney"
SVG_PATH = os.path.join(ROOT_DIR, "docs/design/SuenMoney-sky-blue.svg")
RES_DIR = os.path.join(ROOT_DIR, "android/app/src/main/res")
WEB_PUBLIC = os.path.join(ROOT_DIR, "web/public")

print("[1/5] Extracting master PNG from SVG...")
with open(SVG_PATH, "r", encoding="utf-8") as f:
    svg_content = f.read()

m = re.search(r'data:image/png;base64,([A-Za-z0-9+/=]+)', svg_content)
if not m:
    raise RuntimeError("Could not find base64 PNG in SVG!")

raw_png = base64.b64decode(m.group(1))
import io
master_squircle = Image.open(io.BytesIO(raw_png)).convert("RGBA")
W, H = master_squircle.size
print(f"Master image size: {W}x{H}")

print("[2/5] Creating seamless full-bleed background & safe-zone adaptive base...")
# Raycast outward for transparent corners
pix = master_squircle.load()
bleed = Image.new("RGBA", (W, H))
bleed_pix = bleed.load()

for y in range(H):
    for x in range(W):
        bleed_pix[x, y] = pix[x, y]

for y in range(H):
    for x in range(W):
        if pix[x, y][3] < 250:
            dx = 512 - x
            dy = 512 - y
            dist = math.hypot(dx, dy)
            if dist == 0:
                continue
            ux = dx / dist
            uy = dy / dist
            step = 1.0
            found = None
            while step < dist:
                cx = int(x + ux * step)
                cy = int(y + uy * step)
                if pix[cx, cy][3] >= 250:
                    found = pix[cx, cy]
                    break
                step += 1.0
            if found:
                bleed_pix[x, y] = (found[0], found[1], found[2], 255)

# Adaptive Icon Base (scale 0.82 for comfortable safe-zone padding)
scale = 0.82
sw = int(W * scale)
sh = int(H * scale)
scaled_bleed = bleed.resize((sw, sh), Image.Resampling.LANCZOS)

c00 = bleed.getpixel((0, 0))
c10 = bleed.getpixel((W - 1, 0))
c01 = bleed.getpixel((0, H - 1))
c11 = bleed.getpixel((W - 1, H - 1))

adaptive_base = Image.new("RGBA", (W, H))
canv_pix = adaptive_base.load()
for y in range(H):
    fy = y / H
    for x in range(W):
        fx = x / W
        r = int((1-fx)*(1-fy)*c00[0] + fx*(1-fy)*c10[0] + (1-fx)*fy*c01[0] + fx*fy*c11[0])
        g = int((1-fx)*(1-fy)*c00[1] + fx*(1-fy)*c10[1] + (1-fx)*fy*c01[1] + fx*fy*c11[1])
        b = int((1-fx)*(1-fy)*c00[2] + fx*(1-fy)*c10[2] + (1-fx)*fy*c01[2] + fx*fy*c11[2])
        canv_pix[x, y] = (r, g, b, 255)

ox = (W - sw) // 2
oy = (H - sh) // 2
feather_mask = Image.new("L", (sw, sh), 255)
for i in range(25):
    alpha = int(255 * (i / 25.0))
    for x in range(sw):
        if i < sh:
            feather_mask.putpixel((x, i), min(feather_mask.getpixel((x, i)), alpha))
            feather_mask.putpixel((x, sh - 1 - i), min(feather_mask.getpixel((x, sh - 1 - i)), alpha))
    for y in range(sh):
        if i < sw:
            feather_mask.putpixel((i, y), min(feather_mask.getpixel((i, y)), alpha))
            feather_mask.putpixel((sw - 1 - i, y), min(feather_mask.getpixel((sw - 1 - i, y)), alpha))

adaptive_base.paste(scaled_bleed, (ox, oy), feather_mask)

print("[3/5] Generating Android mipmap launcher icons...")
densities = {
    "mdpi": {"legacy": 48, "foreground": 108},
    "hdpi": {"legacy": 72, "foreground": 162},
    "xhdpi": {"legacy": 96, "foreground": 216},
    "xxhdpi": {"legacy": 144, "foreground": 324},
    "xxxhdpi": {"legacy": 192, "foreground": 432},
}

for density, sizes in densities.items():
    folder = os.path.join(RES_DIR, f"mipmap-{density}")
    os.makedirs(folder, exist_ok=True)
    
    # 1. ic_launcher.png (squircle)
    sq_size = sizes["legacy"]
    sq_icon = master_squircle.resize((sq_size, sq_size), Image.Resampling.LANCZOS)
    sq_icon.save(os.path.join(folder, "ic_launcher.png"))
    
    # 2. ic_launcher_round.png (circle masked)
    round_icon = Image.new("RGBA", (sq_size, sq_size), (0, 0, 0, 0))
    c_mask = Image.new("L", (sq_size, sq_size), 0)
    c_draw = ImageDraw.Draw(c_mask)
    margin = max(1, int(sq_size * 0.02))
    c_draw.ellipse((margin, margin, sq_size - margin, sq_size - margin), fill=255)
    
    # for round icon, scale adaptive_base to sq_size
    round_base = adaptive_base.resize((sq_size, sq_size), Image.Resampling.LANCZOS)
    round_icon.paste(round_base, (0, 0), c_mask)
    round_icon.save(os.path.join(folder, "ic_launcher_round.png"))
    
    # 3. ic_launcher_foreground.png (adaptive foreground)
    fg_size = sizes["foreground"]
    fg_icon = adaptive_base.resize((fg_size, fg_size), Image.Resampling.LANCZOS)
    fg_icon.save(os.path.join(folder, "ic_launcher_foreground.png"))
    
    print(f"  -> Generated {density}: sq={sq_size}, round={sq_size}, fg={fg_size}")

print("[4/5] Generating Android splash screens...")
splashes = {
    "drawable/splash.png": (480, 320, 110),
    "drawable-port-mdpi/splash.png": (320, 480, 110),
    "drawable-port-hdpi/splash.png": (480, 800, 160),
    "drawable-port-xhdpi/splash.png": (720, 1280, 240),
    "drawable-port-xxhdpi/splash.png": (960, 1600, 300),
    "drawable-port-xxxhdpi/splash.png": (1280, 1920, 360),
    "drawable-land-mdpi/splash.png": (480, 320, 110),
    "drawable-land-hdpi/splash.png": (800, 480, 150),
    "drawable-land-xhdpi/splash.png": (1280, 720, 200),
    "drawable-land-xxhdpi/splash.png": (1600, 960, 260),
    "drawable-land-xxxhdpi/splash.png": (1920, 1280, 320),
}

for rel_path, (width, height, icon_dim) in splashes.items():
    target_path = os.path.join(RES_DIR, rel_path)
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    
    splash_img = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    logo_part = master_squircle.resize((icon_dim, icon_dim), Image.Resampling.LANCZOS)
    
    # Center with slight upward optical offset for portrait
    off_x = (width - icon_dim) // 2
    off_y = (height - icon_dim) // 2
    if height > width:
        off_y -= int(height * 0.03)
        
    splash_img.paste(logo_part, (off_x, off_y), logo_part)
    splash_img.convert("RGB").save(target_path)
    print(f"  -> Generated {rel_path} ({width}x{height})")

print("[5/5] Generating Web and PWA public assets...")
os.makedirs(WEB_PUBLIC, exist_ok=True)

# 1. favicon.png
master_squircle.resize((32, 32), Image.Resampling.LANCZOS).save(os.path.join(WEB_PUBLIC, "favicon.png"))

# 2. apple-touch-icon.png
master_squircle.resize((180, 180), Image.Resampling.LANCZOS).save(os.path.join(WEB_PUBLIC, "apple-touch-icon.png"))

# 3. icon.png (192x192)
master_squircle.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(WEB_PUBLIC, "icon.png"))

# 4. icon-512.png (512x512)
master_squircle.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(WEB_PUBLIC, "icon-512.png"))

# 5. logo.png (512x512)
master_squircle.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(WEB_PUBLIC, "logo.png"))

# 6. logo.svg
import shutil
shutil.copyfile(SVG_PATH, os.path.join(WEB_PUBLIC, "logo.svg"))

print("All Android and Web assets successfully generated!")
