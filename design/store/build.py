#!/usr/bin/env python3
"""Generate and build the App Store screenshot panels.

Ten panels, five per language (docs/STORE.md section 4). Each is a composite:
a kicker, a benefit headline, a caption naming the mechanism, and a REAL
committed screenshot as evidence - so a panel can never show a screen the build
does not have.

    python3 design/store/build.py --dry-run     # layout only, free
    python3 design/store/build.py               # build all ten
"""
import argparse, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

CACHE = os.path.join(HERE, ".cache")


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
    im = Image.open(src).convert("RGBA")
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


def shared_background(w=1290, h=2796):
    """The one background every panel shares, drawn once and reused.

    Ellipse layers gave hard arcs across the frame - a rendering artefact, not a
    wash. This paints the glows and blurs them heavily, so the ten panels read as
    one family in the carousel with no visible edge anywhere.
    """
    from PIL import Image, ImageDraw, ImageFilter
    os.makedirs(CACHE, exist_ok=True)
    dst = os.path.join(CACHE, "background.png")
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

    ("03", "RV.57-capture-prefill", "P4.9b-settings-guest",
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
  width: 1290
  height: 2796
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


def source_for(shot):
    """The image a panel actually draws - a real receipt where the shot is a mock."""
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
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
