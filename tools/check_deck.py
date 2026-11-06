#!/usr/bin/env python3
"""Check that the deck in lib/main.dart and the images in assets/ agree.

    python tools\\check_deck.py            # report + exit 1 on any problem
    python tools\\check_deck.py --quiet    # only print problems

Every card needs both images, and every image needs a card (an orphan image is
dead weight in the Windows build, the APK and the web bundle). Also checks the
card numbers run 1..N in booklet order, that every card's family is listed in
kFamilies, and that no listed family is empty.

tools\\build_weed_cards.py writes both the images and this Dart list, so a
mismatch means one of the two was edited by hand.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN = ROOT / "lib" / "main.dart"
FRONT_DIR = ROOT / "assets" / "front"   # <id>.jpg, name painted out
BACK_DIR = ROOT / "assets" / "back"     # <id>.jpg, as printed

# A Dart single-quoted string, apostrophes escaped as \' (Paddy's Lucern).
_STR = r"((?:[^'\\]|\\.)*)"
CARD = re.compile(
    r"FlashCard\(\s*id:\s*'([^']+)',\s*title:\s*'" + _STR + r"',\s*number:\s*(\d+),"
    r"\s*sci:\s*'" + _STR + r"',\s*family:\s*'([^']+)'\s*\)"
)
FAMILY = re.compile(r"^\s*'([A-Z][A-Za-z]+)':\s*'([^']+)',", re.M)


def parse_main(text: str):
    deck = re.search(r"const List<FlashCard> kDeck = <FlashCard>\[(.*?)\];",
                     text, re.S)
    fams = re.search(r"const Map<String, String> kFamilies = "
                     r"<String, String>\{(.*?)\};", text, re.S)
    if not deck or not fams:
        return [], []
    cards = CARD.findall(deck.group(1))
    return cards, FAMILY.findall(fams.group(1))


def main() -> int:
    quiet = "--quiet" in sys.argv
    cards, families = parse_main(MAIN.read_text(encoding="utf-8"))
    if not cards:
        print("FAIL: no FlashCard entries parsed from lib/main.dart")
        return 1

    problems = []
    ids = [c[0] for c in cards]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        problems.append(f"duplicate ids in kDeck: {dupes}")

    # Booklet order: the page number is what the card is named after.
    numbers = [int(c[2]) for c in cards]
    if numbers != list(range(1, len(cards) + 1)):
        problems.append(f"card numbers are not 1..{len(cards)} in order: "
                        f"{numbers}")

    fronts = {p.stem for p in FRONT_DIR.glob("*.jpg")}
    backs = {p.stem for p in BACK_DIR.glob("*.jpg")}
    deck = set(ids)
    for label, images in (("front", fronts), ("back", backs)):
        missing = sorted(deck - images)
        orphan = sorted(images - deck)
        if missing:
            problems.append(f"cards with no {label} image: {missing}")
        if orphan:
            problems.append(f"{label} images with no card (dead weight): {orphan}")
    unpaired = sorted(fronts ^ backs)
    if unpaired:
        problems.append(f"images not paired front<->back: {unpaired}")

    fam_names = {f for f, _common in families}
    if len(fam_names) != len(families):
        problems.append("kFamilies lists a family twice")
    used = {c[4] for c in cards}
    for _id, title, _n, sci, family in cards:
        if not title.strip():
            problems.append(f"card {_id!r} has an empty title")
        if not sci.strip():
            problems.append(f"card {_id!r} has no scientific name")
        if family not in fam_names:
            problems.append(f"card {_id!r} has unknown family {family!r}")
    for family in sorted(used - fam_names):
        problems.append(f"family {family!r} is used by cards but not in kFamilies")
    for family in sorted(fam_names - used):
        problems.append(f"family {family!r} in kFamilies has no cards")

    if not quiet:
        print(f"cards: {len(cards)}   front images: {len(fronts)}   "
              f"back images: {len(backs)}   families: {len(fam_names)}")
        per_family = {}
        for _id, _t, _n, _s, family in cards:
            per_family[family] = per_family.get(family, 0) + 1
        for family in sorted(per_family, key=lambda k: (-per_family[k], k)):
            print(f"  {family:20s} {per_family[family]}")
        total = (sum(p.stat().st_size for p in FRONT_DIR.glob("*.jpg"))
                 + sum(p.stat().st_size for p in BACK_DIR.glob("*.jpg")))
        print(f"image bytes bundled: {total / 1e6:.1f} MB")

    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  - " + p)
        return 1
    if not quiet:
        print("\nOK: deck and assets agree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
