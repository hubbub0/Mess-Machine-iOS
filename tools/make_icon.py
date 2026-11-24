#!/usr/bin/env python3
"""Make the iPhone app icon from the Android launcher art in core/ (Tyler's drawing on the ink background).

Android's adaptive icon shows the middle 72 of its 108 dp canvas; that same square becomes the 1024 px iOS icon,
opaque as Apple requires. Run from the repo root after the core/ pin moves: python3 tools/make_icon.py
"""
from PIL import Image

SRC = "core/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png"
OUT = "ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
INK = (0x18, 0x16, 0x1A, 255)  # @color/ink in core/app/src/main/res/values/colors.xml

fg = Image.open(SRC).convert("RGBA")
w = fg.width
bg = Image.new("RGBA", fg.size, INK)
bg.alpha_composite(fg)
cut = round(w * 18 / 108)
icon = bg.crop((cut, cut, w - cut, w - cut)).resize((1024, 1024), Image.LANCZOS).convert("RGB")
icon.save(OUT, optimize=True)
print("wrote", OUT, icon.size)
