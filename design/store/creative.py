#!/usr/bin/env python3
"""Build the iOS 27 creative assets: the product page header and the search-results image.

docs/STORE.md section 9 owns what they say and why. Each is a composite: a
generated photo as the ground, a REAL committed screenshot in a phone frame as
the evidence, and the slogan. The pump screenshot's photo area is replaced by a
brand-free copy of the same photo (the real one carries a fuel brand and a
soft-drink advert, which the store forbids) by a close-up crop of the same photo:
the display alone, with one sticker painted out, so the digits stay the real ones.

    python3 design/store/creative.py        # needs Pillow; writes design/store/creative/
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "..", "screenshots")
# Marketing captures (not a task's record), shared with the site's mount.
MARKETING = os.path.join(HERE, "site")
ASSETS = os.path.join(HERE, "assets")
OUT = os.path.join(HERE, "creative")
FONT = "/System/Library/Fonts/SFNS.ttf"

MIDNIGHT = (16, 19, 24)
INK = (234, 237, 242)
TAILLIGHT = (244, 80, 58)

# Accepted sizes (App Store Connect Help -> Creative assets specifications).
HEADER = (3840, 1646)   # 21:9
SEARCH = (3840, 2560)   # 3:2, the maximum

# The photo rectangle inside SH.18-capture-verify-pump{,-ru}.png, measured.
PUMP_RECT = {"en": (260, 380, 946, 1663), "ru": (244, 385, 962, 1663)}

# Per asset: where the slogan starts and where the phone's centre sits, as
# fractions of the width.
LAYOUT = {"header": (0.15, 0.56), "search": (0.07, 0.47)}

ASSETS_LIST = [
    # name, size, ground photo, screenshot stem, lines (text, colour), text-left x, phone-centre x
    ("header", HEADER, "creative-header-ground.png", "SH.18-capture-verify-pump",
     {"ru": [("Чека нет?", TAILLIGHT), ("Снимите табло", INK), ("колонки", INK)],
      "en": [("No receipt?", TAILLIGHT), ("Snap the pump", INK)]}),
    ("search", SEARCH, "creative-search-ground.png", "home-month",
     {"ru": [("Знаете, во что", INK), ("вам обходится", INK), ("машина?", TAILLIGHT)],
      "en": [("What your car", INK), ("burns, and", INK), ("what it costs", TAILLIGHT)]}),
]


def font(size):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name("Bold")
    except (OSError, ValueError):
        pass
    return f


def cover(im, size):
    w, h = size
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def screenshot(stem, lang):
    name = stem + ("-ru" if lang == "ru" else "")
    src = os.path.join(MARKETING, name + ".png")
    if not os.path.exists(src):
        src = os.path.join(SHOTS, name + ".png")
    im = Image.open(src).convert("RGB")
    clean_path = os.path.join(ASSETS, "pump-display-clean.png")
    if stem.startswith("SH.18-capture-verify-pump") and os.path.exists(clean_path):
        x0, y0, x1, y1 = PUMP_RECT[lang]
        clean = Image.open(clean_path).convert("RGB")
        # A close-up, letterboxed on black the way the check screen shows a photo.
        im.paste((0, 0, 0), (x0, y0, x1, y1))
        s = (x1 - x0) / clean.width
        clean = clean.resize((x1 - x0, round(clean.height * s)), Image.LANCZOS)
        im.paste(clean, (x0, y0 + (y1 - y0 - clean.height) // 2))
    return im


def phone(shot, height):
    """The screenshot in a plain dark bezel with rounded corners and a soft shadow."""
    s = height / shot.height
    shot = shot.resize((round(shot.width * s), height), Image.LANCZOS)
    bezel = round(height * 0.018)
    w, h = shot.width + 2 * bezel, shot.height + 2 * bezel
    r_out, r_in = round(w * 0.14), round(shot.width * 0.13)
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, w - 1, h - 1], r_out, fill=(8, 9, 12, 255),
                                           outline=(58, 64, 74, 255), width=max(2, bezel // 6))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], r_in, fill=255)
    body.paste(shot, (bezel, bezel), mask)
    pad = round(height * 0.08)
    shadow = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([pad, pad + pad // 3, pad + w, pad + h + pad // 3],
                                             r_out, fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(pad // 2))
    shadow.alpha_composite(body, (pad, pad))
    return shadow, pad


def build(name, size, ground, stem, lines, lang):
    W, H = size
    canvas = cover(Image.open(os.path.join(ASSETS, ground)).convert("RGB"), size).convert("RGBA")
    # A midnight wash from the left so the slogan reads on any photo.
    row = Image.new("RGBA", (W, 1))
    row.putdata([MIDNIGHT + (round(235 * max(0.0, min(1.0, (0.62 - x / W) / 0.40))),)
                 for x in range(W)])
    canvas.alpha_composite(row.resize(size))

    # The header keeps its slogan and phone in the central band: the store crops
    # it for narrower screens, and Apple asks for a centred focal point.
    # The photo's own subject (the pump, the car) stays visible on the right.
    band_l, phone_cx = LAYOUT[name]
    band_l = round(W * band_l)
    ph_h = round(H * (0.84 if name == "header" else 0.86))
    ph, pad = phone(screenshot(stem, lang), ph_h)
    ph_x = round(W * phone_cx) - ph.width // 2
    ph_y = (H - ph.height) // 2 + pad // 3
    canvas.alpha_composite(ph, (ph_x, ph_y))

    text_w = ph_x + pad - band_l - round(W * 0.05)
    size_px = round(H * (0.105 if name == "header" else 0.095))
    while True:
        f = font(size_px)
        widths = [f.getlength(t) for t, _ in lines]
        if max(widths) <= text_w or size_px < 60:
            break
        size_px -= 4
    lh = round(size_px * 1.12)
    y = (H - lh * len(lines)) // 2
    d = ImageDraw.Draw(canvas)
    for t, colour in lines:
        d.text((band_l, y), t, font=f, fill=colour)
        y += lh

    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"{name}-{lang}.png")
    canvas.convert("RGB").save(dst)   # the store rejects an alpha channel
    return dst


if __name__ == "__main__":
    for name, size, ground, stem, by_lang in ASSETS_LIST:
        for lang, lines in by_lang.items():
            print(build(name, size, ground, stem, lines, lang))
