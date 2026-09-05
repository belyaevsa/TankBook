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
  - id: wash
    source: fill
    area: {{cols: 1-12, rows: 1-6}}
    color: "#161C25"
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
    path: ../screenshots/{shot}.png
    fit: contain
    radius: 40
"""


def write_specs():
    paths = []
    for pid, shot_en, shot_ru, en, ru in PANELS:
        for lang, shot, (kicker, headline, caption) in (("en", shot_en + "", en),
                                                        ("ru", shot_ru + "-ru", ru)):
            path = os.path.join(HERE, f"panel-{pid}-{lang}.yaml")
            with open(path, "w", encoding="utf-8") as f:
                f.write(SPEC.format(pid=pid, lang=lang, kicker=kicker, headline=headline,
                                    caption=caption, shot=shot))
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
