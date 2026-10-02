#!/usr/bin/env python3
"""Builds the bundled city dictionary (docs/SCHEMA.md -> Places) from GeoNames.

Input: a directory holding GeoNames' cities15000.txt, alternateNamesV2.txt and
countryInfo.txt (https://download.geonames.org/export/dump/, CC BY 4.0), plus
scripts/data/city-aliases.tsv. Output: ios/Sources/TankbookCore/Places/Cities.seed.json,
one city per line so a regeneration is a readable diff.

    python3 scripts/build-city-dictionary.py <geonames-dir> [--version YYYYMMDD]

Each city keeps its GeoNames name, its English and Russian names where GeoNames has
them, and the matching aliases: the names in English, Russian and the country's first
two languages, Latin or Cyrillic script only, never historic or colloquial forms.
"""
import argparse, json, os, re, sys, unicodedata
from datetime import date

COUNTRIES = [
    "EE", "LV", "LT", "FI", "SE", "NO", "DK", "IS", "DE", "AT", "CH", "LI", "PL", "CZ", "SK",
    "HU", "SI", "HR", "BA", "RS", "ME", "MK", "AL", "XK", "BG", "RO", "MD", "UA", "BY", "RU",
    "KZ", "UZ", "KG", "TJ", "TM", "GE", "AM", "AZ", "TR", "GR", "CY", "IT", "SM", "MT", "FR",
    "MC", "ES", "PT", "AD", "BE", "NL", "LU", "IE", "GB",
]
SCRIPT = re.compile(r"^[A-Za-zÀ-ɏЀ-ӿ' .\-]+$")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("geonames")
    ap.add_argument("--version", type=int, default=int(date.today().strftime("%Y%m%d")))
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    wanted = set(COUNTRIES)

    languages = {}
    for line in open(os.path.join(args.geonames, "countryInfo.txt"), encoding="utf-8"):
        if line.startswith("#"):
            continue
        f = line.rstrip("\n").split("\t")
        if len(f) > 15 and f[0] in wanted:
            languages[f[0]] = [l.split("-")[0] for l in f[15].split(",") if l][:2]

    cities = {}
    for line in open(os.path.join(args.geonames, "cities15000.txt"), encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        # A district of a larger city (PPLX, "Lasnamäe" in Tallinn) is not where
        # a car is kept; the city itself is in the list.
        if f[8] not in wanted or f[7] == "PPLX":
            continue
        cities[int(f[0])] = {
            "id": int(f[0]), "name": f[1], "ascii": f[2], "c": f[8],
            "lat": round(float(f[4]), 4), "lon": round(float(f[5]), 4),
            "pop": int(f[14] or 0), "names": {}, "alt": set(),
        }

    for line in open(os.path.join(args.geonames, "alternateNamesV2.txt"), encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) < 4:
            continue
        gid = int(f[1])
        city = cities.get(gid)
        if city is None:
            continue
        lang, name = f[2], f[3].strip()
        preferred = len(f) > 4 and f[4] == "1"
        colloquial = len(f) > 6 and f[6] == "1"
        historic = len(f) > 7 and f[7] == "1"
        if colloquial or historic or not SCRIPT.match(name) or not 2 <= len(name) <= 40:
            continue
        keep = {"en", "ru"} | set(languages.get(city["c"], []))
        if lang not in keep:
            continue
        if lang in ("en", "ru") and (preferred or lang not in city["names"]):
            city["names"][lang] = name
        city["alt"].add(name)

    alias_path = os.path.join(root, "scripts", "data", "city-aliases.tsv")
    for line in open(alias_path, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        gid, alias = line.rstrip("\n").split("\t", 1)
        if int(gid) in cities:
            cities[int(gid)]["alt"].add(alias.strip())
        else:
            sys.exit(f"alias for unknown geonameid {gid}")

    rows = []
    for city in sorted(cities.values(), key=lambda c: (c["c"], -c["pop"], c["id"])):
        en = city["names"].get("en", city["name"])
        ru = city["names"].get("ru")
        alt = sorted({a for a in city["alt"] | {city["ascii"]} if a not in (city["name"], en, ru)})
        row = {"id": city["id"], "name": city["name"], "en": en, "c": city["c"],
               "lat": city["lat"], "lon": city["lon"], "pop": city["pop"]}
        if ru:
            row["ru"] = ru
        if alt:
            row["alt"] = alt
        rows.append(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")))

    out = os.path.join(root, "ios", "Sources", "TankbookCore", "Places", "Cities.seed.json")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write('{"version":%d,"source":"GeoNames cities15000 (https://www.geonames.org), CC BY 4.0",\n"cities":[\n' % args.version)
        fh.write(",\n".join(rows))
        fh.write("\n]}\n")
    print(f"{len(rows)} cities, {os.path.getsize(out)} bytes -> {out}")

if __name__ == "__main__":
    main()
