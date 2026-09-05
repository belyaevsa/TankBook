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

# panel id, screenshot stem, EN (kicker, headline, caption), RU (kicker, headline, caption)
PANELS = [
    ("01-two-doors", "RV.57-capture-prefill",
     ("TWO DOORS, ALWAYS", "Snap it or type it",
      "Both take seconds. Typing is a peer path, never the failure branch."),
     ("ДВА ПУТИ, ВСЕГДА", "Сфотографируйте или введите",
      "И то и другое - секунды. Ручной ввод равноправен, а не запасной вариант.")),

    ("02-cross-check", "P2.3-confirm",
     ("THE ARITHMETIC, SHOWN", "Litres x price, checked in front of you",
      "When the three numbers disagree, the app says so. Nothing is corrected behind your back."),
     ("АРИФМЕТИКА НА ВИДУ", "Литры x цена - проверка при вас",
      "Если три числа не сходятся, приложение скажет прямо. Ничего не правится втихую.")),

    ("03-trends", "P1.10-trends",
     ("WHAT IT COSTS TO DRIVE", "Consumption and cost, per car",
      "L/100 km or MPG, cost per kilometre, monthly spend - petrol, diesel and EV in one history."),
     ("СКОЛЬКО СТОИТ ЕЗДА", "Расход и стоимость по каждой машине",
      "Л/100 км, стоимость километра, траты за месяц - бензин, дизель и электро в одной истории.")),

    ("04-currency", "P2.5-confirm-foreign",
     ("ANY CURRENCY, KEPT HONEST", "Fill up abroad, keep both amounts",
      "What you paid, and what it was worth at that day's rate. History never shifts under you."),
     ("ЛЮБАЯ ВАЛЮТА", "Заправка за границей - обе суммы",
      "Сколько заплатили и сколько это по курсу того дня. История потом не поедет.")),

    ("05-yours", "P6.5-home-log",
     ("YOURS TO KEEP", "No account. Works offline.",
      "Every screen works with no sign-in at all. Export is always free. No ads, ever."),
     ("ВСЁ ОСТАЁТСЯ У ВАС", "Без аккаунта. Работает офлайн.",
      "Все экраны работают без регистрации. Экспорт всегда бесплатный. Без рекламы.")),
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
    for pid, shot, en, ru in PANELS:
        for lang, (kicker, headline, caption) in (("en", en), ("ru", ru)):
            suffix = "" if lang == "en" else "-ru"
            path = os.path.join(HERE, f"panel-{pid}-{lang}.yaml")
            with open(path, "w", encoding="utf-8") as f:
                f.write(SPEC.format(pid=pid, lang=lang, kicker=kicker, headline=headline,
                                    caption=caption, shot=shot + suffix))
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
