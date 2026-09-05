#!/usr/bin/env python3
"""Generate and build the App Store screenshot panels.

Ten panels, five per language (docs/STORE.md section 4). Each is a composite:
a kicker, a benefit headline, a caption naming the mechanism, and a REAL
committed screenshot as evidence - so a panel can never show a screen the build
does not have.

    python3 design/store/build.py --dry-run     # layout only, free
    python3 design/store/build.py               # build all ten
"""
import argparse, glob, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

CACHE = os.path.join(HERE, ".cache")


def trim_dead_space(im, pad=40):
    """Crop uniform background off the bottom of a screenshot.

    Several screens end in a tall stretch of empty page - a short list, a sheet
    with two rows - and in a panel that reads as a phone with nothing on it. Rows
    matching the bottom-most colour are cropped away, leaving `pad` so the last
    element does not touch the corner.
    """
    w, h = im.size
    px = im.convert("RGB").load()
    ground = px[w // 2, h - 1]

    def empty(y):
        return all(max(abs(a - b) for a, b in zip(px[x, y], ground)) < 12
                   for x in range(0, w, 7))

    y = h - 1
    while y > h // 2 and empty(y):
        y -= 1
    if h - y < pad * 2:
        return im
    return im.crop((0, 0, w, min(h, y + pad)))


def rounded(stem, src=None):
    """A rounded-corner RGBA copy of a committed screenshot.

    The device layer's own `radius` clips the LAYER BOX, and `fit: contain`
    letterboxes the image inside it, so the screenshot's own corners stayed
    square. Rounding the source is the reliable way: alpha corners, cached by
    name, and the committed screenshot is never modified.
    """
    from PIL import Image, ImageDraw
    os.makedirs(CACHE, exist_ok=True)
    src = src or os.path.join(HERE, "..", "screenshots", stem + ".png")
    dst = os.path.join(CACHE, os.path.basename(src)[:-4] + "-rounded.png")
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return dst
    im = trim_dead_space(Image.open(src).convert("RGBA"))
    r = int(im.width * 0.055)          # a phone-like corner on a phone-shaped shot
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=r, fill=255)
    im.putalpha(mask)
    im.save(dst)
    return dst


RECEIPT = "Spike/ReceiptSpike/fixtures/receipts/receipt-046-circlek-sikupilli-pump5-db0-5580l-ee.jpg"


def viewer_with_real_photo(stem="RV.9-attachment-viewer"):
    """The attachment viewer showing a REAL corpus receipt, not the test mock.

    The committed screenshot is captured from a seeded build, so its viewer holds
    a grey placeholder - honest as a UI record, useless as a store panel about
    keeping the photo. This drops a real fixture receipt into the same image
    region the viewer draws into, so the chrome, the title and the hint are still
    the shipping screen's own pixels.
    """
    from PIL import Image
    os.makedirs(CACHE, exist_ok=True)
    src = os.path.join(HERE, "..", "screenshots", stem + ".png")
    photo = os.path.join(HERE, "..", "..", RECEIPT)
    dst = os.path.join(CACHE, stem + "-real.png")
    if os.path.exists(dst) and os.path.getmtime(dst) >= max(os.path.getmtime(src),
                                                            os.path.getmtime(photo)):
        return dst
    im = Image.open(src).convert("RGB")
    top, bottom = 620, 2380          # the viewer's content area, between the nav bar and the hint
    box_w, box_h = im.width, bottom - top
    im.paste((0, 0, 0), [0, top, box_w, bottom])
    ph = Image.open(photo).convert("RGB")
    ph.thumbnail((box_w, box_h), Image.LANCZOS)
    im.paste(ph, ((box_w - ph.width) // 2, top + (box_h - ph.height) // 2))
    im.save(dst)
    return dst


def shared_background(w=1284, h=2778):
    """The one background every panel shares, drawn once and reused.

    Ellipse layers gave hard arcs across the frame - a rendering artefact, not a
    wash. This paints the glows and blurs them heavily, so the ten panels read as
    one family in the carousel with no visible edge anywhere.
    """
    from PIL import Image, ImageDraw, ImageFilter
    os.makedirs(CACHE, exist_ok=True)
    dst = os.path.join(CACHE, f"background-{w}x{h}.png")
    if os.path.exists(dst):
        return dst
    base = Image.new("RGB", (w, h), "#0C0F14")
    glow = Image.new("RGB", (w, h), "#0C0F14")
    d = ImageDraw.Draw(glow)
    # taillight behind the headline, headlight under the device
    d.ellipse([-w // 2, -h // 4, w + w // 2, h // 2], fill="#3A1A18")
    d.ellipse([-w // 2, h - h // 2, w + w // 2, h + h // 4], fill="#12262E")
    glow = glow.filter(ImageFilter.GaussianBlur(radius=260))
    Image.blend(base, glow, 0.85).save(dst)
    return dst


FINAL = os.path.join(HERE, "final")
APP_STORE_SIZES = {(1242, 2688), (2688, 1242), (1284, 2778), (2778, 1284)}


def export_final():
    """Copy the built panels into final/ as upload-ready files, and check them.

    App Store Connect takes 1242x2688 or 1284x2778 in this slot and REJECTS a PNG
    that carries an alpha channel - imagegen writes RGBA, so each panel is
    flattened onto black here. Returns the list of failures, empty when the set
    is submittable.
    """
    from PIL import Image
    os.makedirs(FINAL, exist_ok=True)
    bad = []
    for src in sorted(glob.glob(os.path.join(OUT, "compositions", "*", "store-*.png"))):
        im = Image.open(src)
        if im.size not in APP_STORE_SIZES:
            bad.append(f"{os.path.basename(src)}: {im.size[0]}x{im.size[1]} is not an accepted size")
            continue
        flat = Image.new("RGB", im.size, (0, 0, 0))
        flat.paste(im, mask=im.split()[3] if im.mode == "RGBA" else None)
        flat.save(os.path.join(FINAL, os.path.basename(src)))
    return bad


PANELS = [
    # EN and RU are DIFFERENT SETS, in different order, from different complaints
    # (docs/STORE.md section 1). Panel 1-3 are what search results show, so each
    # language leads with what that audience is actually angry about.
    #   EN: the phone change destroys the history (Simply Auto, Fuelly, Drivvo)
    #   RU: the app stops being yours - servers off, Pro unpayable, numbers unverifiable
    ("01", "P6.5-home-log", "P6.5-home-log",
     ("YOURS TO KEEP", "Your log. Yours to keep.",
      "No account, ever. The database is on your phone and every screen works offline."),
     ("РАБОТАЕТ БЕЗ СЕРВЕРА", "Откроется, даже если серверы лежат",
      "Аккаунт не нужен. База в телефоне, все экраны работают офлайн.")),

    ("02", "RV.9-attachment-viewer", "P2.3-confirm",
     ("EXPORT, COMPLETE", "The export takes the photos too",
      "Records and the receipt images, in one archive. Free, and not behind a paid tier."),
     ("ЦИФРЫ МОЖНО ПРОВЕРИТЬ", "Литры x цена - проверка на экране",
      "Если три числа не сходятся, приложение скажет прямо. Ничего не правится втихую.")),

    ("03", "P2.1-capture", "P4.9b-settings-guest",
     ("TWO DOORS, ALWAYS", "Snap it or type it",
      "Both take seconds. Typing is a peer path, never the failure branch."),
     ("БЕЗ ПОДПИСКИ", "Ничего не нужно оплачивать",
      "Подписки нет, рекламы нет. Экспорт бесплатный и полный.")),

    ("04", "P2.3-confirm", "RV.48-attachment-recognised",
     ("THE ARITHMETIC, SHOWN", "Litres x price, checked in front of you",
      "A plain warning when the three numbers disagree. Nothing is corrected behind your back."),
     ("ЧЕК ОСТАЁТСЯ У ВАС", "Фото чека хранится в приложении",
      "Не ссылка на галерею: удалите снимок там - в журнале он останется.")),

    ("05", "P1.10-trends", "P3.4-reminders",
     ("BRING YOUR HISTORY", "Consumption and cost, per car",
      "Petrol, diesel and EV in one history. Import from Fuelio, Drivvo, Fuelly and more."),
     ("НЕ ТОЛЬКО ЗАПРАВКИ", "ТО, страховка и напоминания",
      "Ремонты, запчасти, шины и налоги - с фотографиями и напоминаниями по пробегу.")),
]

SPEC = """name: store-{pid}-{lang}

canvas:
  width: 1284
  height: 2778
  background: "#101318"
  padding: 96
  gap: 24
  columns: 12
  rows: 24

style:
  artStyle: flat vector, minimal, high contrast
  colors: ["#F4503A", "#4FC3E8", "#4FD18C"]
  background: "#101318"
  dark: true

layers:
  # THE SHARED BACKGROUND - identical on all ten panels, so the set reads as one
  # family in the store's carousel rather than ten separate pictures. Drawn
  # locally: a base ground, a taillight glow behind the headline and a headlight
  # glow under the device, both at low opacity.
  - id: ground
    source: image
    bleed: true
    path: {bg_path}
    fit: cover

  - id: wash
    source: fill
    area: {{cols: 1-12, rows: 1-6}}
    color: "#161C25"
    opacity: 0.92
    radius: 32

  - id: kicker
    source: text
    area: {{cols: 1-12, rows: 1}}
    text: "{kicker}"
    role: caption
    font: {{vAlign: bottom, align: center, color: "#FF8A75"}}

  - id: headline
    source: text
    area: {{cols: 1-12, rows: 2-4}}
    text: "{headline}"
    role: display
    fitText: balance
    font: {{vAlign: middle, align: center, color: "#EAEDF2"}}

  - id: caption
    source: text
    area: {{cols: 1-12, rows: 5-6}}
    text: "{caption}"
    role: subtitle
    fitText: shrink
    font: {{vAlign: top, align: center, color: "#9FB0C4"}}

  - id: device
    source: image
    area: {{cols: 1-12, rows: 7-24}}
    path: {shot_path}
    fit: contain
"""


def capture_without_hints(stem="P2.1-capture"):
    """The capture screen cropped down to viewfinder, modes and the shutter.

    Two bands of in-app text are cut out: the alpha-testing notice, which dates
    a store panel the day it stops being true, and the line claiming receipts,
    pump displays and the fiscal QR are detected automatically - a claim the
    listing may not make (`docs/STORE.md`, the copy rule; pump mode ships off).
    The bands are removed, not painted over, so nothing is faked in their place.
    """
    from PIL import Image
    os.makedirs(CACHE, exist_ok=True)
    src = os.path.join(HERE, "..", "screenshots", stem + ".png")
    dst = os.path.join(CACHE, stem + "-trimmed.png")
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return dst
    im = Image.open(src).convert("RGB")
    cuts = [(1690, 1810), (2000, 2260)]        # measured off the shot
    keep, y = [], 0
    for a, b in cuts:
        keep.append(im.crop((0, y, im.width, a)))
        y = b
    keep.append(im.crop((0, y, im.width, im.height)))
    out = Image.new("RGB", (im.width, sum(k.height for k in keep)))
    y = 0
    for k in keep:
        out.paste(k, (0, y))
        y += k.height
    out.save(dst)
    return dst


def collapse_interior_gap(stem, keep=160):
    """Squeeze the one long empty stretch in the middle of a short screen.

    A sheet with five rows leaves half a phone of empty page below them, and in a
    panel that reads as a screen with nothing on it. The longest interior run of
    background rows is cut down to `keep`; the rows above and below it, including
    the page dots and the buttons, are untouched.
    """
    from PIL import Image
    os.makedirs(CACHE, exist_ok=True)
    src = os.path.join(HERE, "..", "screenshots", stem + ".png")
    dst = os.path.join(CACHE, stem + "-collapsed.png")
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return dst
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    ground = px[w // 2, h - 1]

    def empty(y):
        return all(max(abs(a - b) for a, b in zip(px[x, y], ground)) < 12
                   for x in range(0, w, 7))

    best = run = None
    for y in range(h):
        if empty(y):
            run = (run[0], y) if run else (y, y)
            if not best or run[1] - run[0] > best[1] - best[0]:
                best = run
        else:
            run = None
    if not best or best[1] - best[0] < keep * 2:
        return src
    top = im.crop((0, 0, w, best[0] + keep // 2))
    bot = im.crop((0, best[1] - keep // 2, w, h))
    out = Image.new("RGB", (w, top.height + bot.height))
    out.paste(top, (0, 0))
    out.paste(bot, (0, top.height))
    out.save(dst)
    return dst


def source_for(shot):
    """The image a panel actually draws - a real receipt where the shot is a mock."""
    if shot == "RV.48-attachment-recognised-ru":
        return collapse_interior_gap(shot)
    if shot == "P2.1-capture":
        return capture_without_hints(shot)
    if shot == "RV.9-attachment-viewer":
        return viewer_with_real_photo(shot)
    return None


def write_specs():
    paths = []
    for pid, shot_en, shot_ru, en, ru in PANELS:
        for lang, shot, (kicker, headline, caption) in (("en", shot_en + "", en),
                                                        ("ru", shot_ru + "-ru", ru)):
            path = os.path.join(HERE, f"panel-{pid}-{lang}.yaml")
            with open(path, "w", encoding="utf-8") as f:
                f.write(SPEC.format(pid=pid, lang=lang, kicker=kicker, headline=headline,
                                    caption=caption, shot_path=rounded(shot, source_for(shot)),
                                    bg_path=shared_background()))
            paths.append(path)
    return paths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    specs = write_specs()
    print(f"wrote {len(specs)} specs")
    failures = 0
    for spec in specs:
        cmd = ["imagegen", "compose", os.path.basename(spec), "-o", OUT, "--format", "png"]
        if args.dry_run:
            cmd.append("--dry-run")
        r = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
        tail = [l for l in r.stdout.split("\n") if "Compliance" in l or "Layout" in l
                or "FAILED" in l or "warn:" in l]
        print(f"{os.path.basename(spec):28} {' | '.join(t.strip() for t in tail) or 'ok'}")
        if r.returncode != 0:
            failures += 1
    if not args.dry_run:
        bad = export_final()
        for b in bad:
            print("REJECT " + b)
        print(f"exported {len(glob.glob(os.path.join(FINAL, '*.png')))} panels to final/")
        failures += len(bad)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
