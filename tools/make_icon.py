#!/usr/bin/env python3
"""Make the iPhone app icon from core/ (Nov 27: the teardrop eye).

core/tools/icons/launcher.py draws the store icons; its icon-1024.png is the App Store size, opaque as Apple requires,
so this copies it. Older pins without it fall back to the Android launcher art (the middle 72 of the 108 dp canvas on
its background layer, or on ink). Run from the repo root after the core/ pin moves: python3 tools/make_icon.py
"""
import os
from PIL import Image

OUT = "ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
STORE = "core/tools/icons/store/icon-1024.png"
RES = "core/app/src/main/res/mipmap-xxxhdpi/"
INK = (0x18, 0x16, 0x1A, 255)  # @color/ink in core/app/src/main/res/values/colors.xml

if os.path.exists(STORE):
    icon = Image.open(STORE).convert("RGB").resize((1024, 1024), Image.LANCZOS)
else:
    fg = Image.open(RES + "ic_launcher_foreground.png").convert("RGBA")
    bgp = RES + "ic_launcher_background.png"
    bg = Image.open(bgp).convert("RGBA").resize(fg.size) if os.path.exists(bgp) else Image.new("RGBA", fg.size, INK)
    bg.alpha_composite(fg)
    w = fg.width; cut = round(w * 18 / 108)
    icon = bg.crop((cut, cut, w - cut, w - cut)).resize((1024, 1024), Image.LANCZOS).convert("RGB")
icon.save(OUT, optimize=True)
print("wrote", OUT, icon.size)
