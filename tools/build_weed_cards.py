"""Build weeds flashcards from the scanned profile booklet PDF.

The source booklet (default C:/weeds/weeds_revised_001.pdf, --pdf to point at
another copy; it is big, so it is not kept in this repo) is 45 scanned A4
profile pages, one per weed, in the printed order of the study list. Each PDF
page is a single full-page JPEG, so a card is just that page:

  FRONT -> assets/front/<id>.jpg   the page with the name band painted white,
                                   so the photos are all you see. This is the
                                   side shown first.
  BACK  -> assets/back/<id>.jpg    the page as printed
                                   (name + scientific name + family)

The name band is everything above the first photo. Its bottom edge is found by
looking for a photo-frame corner: a long horizontal dark run that also runs
downwards at both ends. The header's underline is horizontal only, which is
what tells the two apart.

Also writes the Dart `kDeck` / `kFamilies` source that lib/main.dart is built
from (see --dart below).

    python tools\\build_weed_cards.py                 # build every card
    python tools\\build_weed_cards.py --dry-run       # report, write nothing
    python tools\\build_weed_cards.py --dry-run --dart out.dart
                                                       # names/families only
    python tools\\build_weed_cards.py --splice         # also rewrite the
                                                       # kDeck / kFamilies blocks
                                                       # inside lib/main.dart
"""

import argparse
import io
import os
import re
import sys

import numpy as np
import pymupdf
from PIL import Image, ImageFile, ImageDraw

ImageFile.LOAD_TRUNCATED_IMAGES = True

SRC_PDF = r"C:\weeds\weeds_revised_001.pdf"   # the scanned booklet (--pdf to move it)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUDY_LIST = os.path.join(ROOT, "weeds_list.txt")   # copy kept in this repo
STUDY_LIST_OUTSIDE = r"C:\weeds\weeds_list.txt"     # where it was written
OUT_BACK = os.path.join(ROOT, "assets", "back")    # <id>.jpg, page as printed
OUT_FRONT = os.path.join(ROOT, "assets", "front")  # <id>.jpg, name painted out
MAIN_DART = os.path.join(ROOT, "lib", "main.dart")

PAGE_W = 1000          # both cards are written at this width
JPEG_Q = 86
FRAME_RUN_MIN = 200    # px of continuous dark line = a photo frame edge
FRAME_DROP_MIN = 60    # ...and it must run this far down at both ends
SCAN_FROM, SCAN_TO = 0.06, 0.45   # fraction of the page to search

# (list no, id, name on the page, scientific name, family as printed)
DECK = [
    (1,  "green_cestrum",       "Green Cestrum",           "Cestrum parqui",               "Solanaceae"),
    (2,  "flickweed",           "Flickweed",               "Cardamine hirsuta",            "Brassicaceae"),
    (3,  "water_hyacinth",      "Water Hyacinth",          "Eichhornia crassipes",         "Pontederiaceae"),
    (4,  "morning_glory",       "Common Morning Glory",    "Ipomoea purpurea",             "Convolvulaceae"),
    (5,  "lantana",             "Lantana",                 "Lantana camara",               "Verbenaceae"),
    (6,  "lambs_tongue",        "Lamb's Tongue / Plantain", "Plantago lanceolata",         "Plantaginaceae"),
    (7,  "dandelion",           "Dandelion",               "Taraxacum officinale",         "Asteraceae"),
    (8,  "wild_tobacco_bush",   "Wild Tobacco Bush",       "Solanum mauritianum",          "Solanaceae"),
    (9,  "ink_weed",            "Ink Weed",                "Phytolacca octandra",          "Phytolaccaceae"),
    (10, "bindii",              "Bindii - Jo-Jo",          "Soliva sessilis",              "Asteraceae"),
    (11, "madeira_vine",        "Madeira Vine",            "Anredera cordifolia",          "Basellaceae"),
    (12, "large_leaf_privet",   "Large Leaf Privet",       "Ligustrum lucidum",            "Oleaceae"),
    (13, "salvinia",            "Salvinia",                "Salvinia molesta",             "Salviniaceae"),
    (14, "camphor_laurel",      "Camphor Laurel",          "Cinnamomum camphora",          "Lauraceae"),
    (15, "castor_oil_plant",    "Castor Oil Plant",        "Ricinus communis",             "Euphorbiaceae"),
    (16, "common_chickweed",    "Common Chickweed",        "Stellaria media",              "Caryophyllaceae"),
    (17, "alligator_weed",      "Alligator Weed",          "Alternanthera philoxeroides",  "Amaranthaceae"),
    (18, "paddys_lucern",       "Paddy's Lucern",          "Sida rhombifolia",             "Malvaceae"),
    (19, "mother_of_millions",  "Mother of Millions",      "Kalanchoe delagoensis",        "Euphorbiaceae"),
    (20, "cobblers_peg",        "Cobblers Pegs / Pitchforks", "Bidens pilosa",             "Asteraceae"),
    (21, "pettyspurge",         "Pettyspurge",             "Euphorbia peplus",             "Euphorbiaceae"),
    (22, "blackberry",          "Blackberry",              "Rubus fruticosus",             "Rosaceae"),
    (23, "fireweed",            "Fireweed",                "Senecio madagascariensis",     "Asteraceae"),
    (24, "coral_tree",          "Coral Tree",              "Erythrina x sykesii",          "Fabaceae"),
    (25, "curled_dock",         "Curled Dock",             "Rumex crispus",                "Polygonaceae"),
    (26, "pennywort",           "Pennywort",               "Hydrocotyle bonariensis",      "Apiaceae"),
    (27, "bitou_bush",          "Bitou Bush",              "Osteospermum monilifera",      "Asteraceae"),
    (28, "wandering_jew",       "Wandering Jew",           "Tradescantia fluminensis",     "Commelinaceae"),
    (29, "nut_grass",           "Nut Grass",               "Cyperus rotundus",             "Cyperaceae"),
    (30, "canadian_fleabane",   "Canadian Fleabane",       "Conyza canadensis",            "Asteraceae"),
    (31, "catsear",             "Catsear / Flatweed",      "Hypochaeris radicata",         "Asteraceae"),
    (32, "small_leaf_privet",   "Small Leaf Privet",       "Ligustrum sinense",            "Oleaceae"),
    (33, "onion_weed",          "Onion Weed",              "Nothoscordum inodorum",        "Alliaceae"),
    (34, "onion_grass",         "Onion Grass",             "Romulea rosea",                "Iridaceae"),
    (35, "blackberry_nightshade", "Blackberry Nightshade", "Solanum nigrum",               "Solanaceae"),
    (36, "sow_thistle",         "Sow Thistle",             "Sonchus oleraceus",            "Asteraceae"),
    (37, "asparagus_fern",      "Asparagus Fern",          "Asparagus aethiopicus",        "Asparagaceae"),
    (38, "balloon_vine",        "Balloon Vine",            "Cardiospermum grandiflorum",   "Sapindaceae"),
    (39, "crofton_weed",        "Crofton Weed",            "Ageratina adenophora",         "Asteraceae"),
    (40, "purple_top",          "Purple Top",              "Verbena bonariensis",          "Verbenaceae"),
    (41, "parramatta_grass",    "Parramatta Grass",        "Sporobolus africanus",         "Poaceae"),
    (42, "summer_grass",        "Summer Grass",            "Digitaria sanguinalis",        "Poaceae"),
    (43, "panic_veldt_grass",   "Panic Veldt Grass",       "Ehrharta erecta",              "Poaceae"),
    (44, "winter_grass",        "Winter Grass",            "Poa annua",                    "Poaceae"),
    (45, "pampas_grass",        "Pampas Grass",            "Cortaderia selloana",          "Poaceae"),
]

# What each family is commonly called. Only used to make the filter and the
# end-of-deck summary readable; the family names themselves are what the
# booklet prints at the top of each page.
FAMILY_COMMON = {
    "Alliaceae": "onion / garlic",
    "Amaranthaceae": "amaranth / pigweed",
    "Apiaceae": "carrot / parsley",
    "Asparagaceae": "asparagus / lily",
    "Asteraceae": "daisy / sunflower",
    "Basellaceae": "malabar spinach",
    "Brassicaceae": "mustard / cabbage",
    "Caryophyllaceae": "pink / chickweed",
    "Commelinaceae": "spiderwort",
    "Convolvulaceae": "morning glory",
    "Cyperaceae": "sedge",
    "Euphorbiaceae": "spurge",
    "Fabaceae": "pea / legume",
    "Iridaceae": "iris",
    "Lauraceae": "laurel / cinnamon",
    "Malvaceae": "mallow / hibiscus",
    "Oleaceae": "olive / privet",
    "Phytolaccaceae": "pokeweed",
    "Plantaginaceae": "plantain",
    "Poaceae": "grass",
    "Polygonaceae": "dock / knotweed",
    "Pontederiaceae": "water hyacinth",
    "Rosaceae": "rose / bramble",
    "Salviniaceae": "water fern",
    "Sapindaceae": "soapberry / maple",
    "Solanaceae": "nightshade",
    "Verbenaceae": "verbena / lantana",
}

# Manual overrides for pages where the automatic frame detector in frame_top()
# gets the wrong line: page number -> y of the top of the first photo, in the
# native scan pixels of that page.
PHOTO_TOP = {}


def family_bottom(im, frame_top):
    """y of the bottom of the printed family word (the navy capitals), or None.

    The family name is the last line of the name band, and on pages where the
    first row of photos is staggered (winter grass, for example) it sits lower
    than the top of the tallest photo. Painting only to the photo top would
    leave half of it showing, so the paint line takes it into account too.

    Navy = blue well over red and green, and dark enough that sky blue and
    purple flowers do not count. Only words that *start* above the photo top
    are considered, so a blue flower inside a photo is not mistaken for one.
    """
    a = np.asarray(im)
    r = a[..., 0].astype(int)
    g = a[..., 1].astype(int)
    b = a[..., 2].astype(int)
    navy = (b - r > 50) & (b - g > 50) & (b > 70) & (r < 110)

    per_row = max(15, im.width // 80)          # ~15 px at 1240 wide
    rows = np.flatnonzero(navy.sum(axis=1) >= per_row)
    rows = rows[rows <= frame_top + 100]

    groups, start, prev = [], None, None
    for y in rows:
        if start is None or y - prev > 8:       # gap = end of a word
            if start is not None:
                groups.append((start, prev))
            start = y
        prev = y
    if start is not None:
        groups.append((start, prev))

    # A word: starts above the photo top and is no taller than a line of caps.
    words = [(s, e) for s, e in groups if s <= frame_top and e - s <= 60]
    return max(e for _s, e in words) if words else None


def paint_line(im, frame_top, no):
    """Where the white paint stops for one page.

    Normally that is the top of the first photo. But the family word printed
    under the scientific name hangs below the photo top on pages whose first
    row of photos is staggered, and half a family word is still enough to give
    the answer away, so the paint goes a little lower there. A page listed in
    PHOTO_TOP is taken exactly as written.
    """
    if no in PHOTO_TOP:
        return frame_top
    fam = family_bottom(im, frame_top)
    return max(frame_top, fam + 8) if fam else frame_top


def page_scan(doc, pno):
    """The full-page scan for a PDF page, at its native resolution."""
    imgs = doc[pno].get_images(full=True)
    if len(imgs) == 1:
        raw = doc.extract_image(imgs[0][0])["image"]
        im = Image.open(io.BytesIO(raw))
        im.load()
        return im.convert("RGB")
    # Any other layout: render the page instead so nothing is silently dropped.
    pix = doc[pno].get_pixmap(matrix=pymupdf.Matrix(2, 2), colorspace=pymupdf.csRGB)
    return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)


def frame_top(im):
    """y of the first photo frame's top edge, or None.

    A frame corner has a long horizontal dark run that also runs down at (at
    least) one end; the header underline is horizontal only, and the scan is
    faint enough that one corner of a frame can wash out.
    """
    a = np.asarray(im)[:, :, 0] < 180       # dark-ish pixels, red channel
    h, w = a.shape
    for y in range(int(h * SCAN_FROM), int(h * SCAN_TO)):
        padded = np.zeros(w + 2, dtype=np.int8)
        padded[1:-1] = a[y]
        edge = np.flatnonzero(np.diff(padded))
        starts, ends = edge[0::2], edge[1::2]
        if starts.size == 0:
            continue
        lengths = ends - starts
        i = int(np.argmax(lengths))
        if lengths[i] < FRAME_RUN_MIN:
            continue
        x0, x1 = int(starts[i]), int(ends[i]) - 1
        drops = []
        for xc in (x0 + 2, x1 - 2):
            gap = np.flatnonzero(~a[y:, xc])
            drops.append(int(gap[0]) if gap.size else h - y)
        if max(drops) >= FRAME_DROP_MIN:
            return y
    return None


def downscale(im, dst):
    if im.width > PAGE_W:
        r = PAGE_W / im.width
        im = im.resize((PAGE_W, int(im.height * r)), Image.LANCZOS)
    im.save(dst, "JPEG", quality=JPEG_Q)


def parse_study_list(path):
    """{list no: (botanical, common)} from weeds_list.txt, if it is there."""
    out = {}
    try:
        with open(path, encoding="utf-8-sig") as fh:
            for line in fh:
                m = re.match(r"\s*(\d+)\s*,\s*([^,]+?)\s*,\s*(.+?)\s*$", line)
                if m:
                    out[int(m.group(1))] = (m.group(2), m.group(3))
    except OSError:
        pass
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would be written, write nothing")
    ap.add_argument("--dart", metavar="FILE",
                    help="write the kDeck / kFamilies Dart source to FILE")
    ap.add_argument("--splice", action="store_true",
                    help="rewrite kDeck / kFamilies inside lib/main.dart")
    ap.add_argument("--pdf", default=SRC_PDF, metavar="FILE",
                    help="the scanned booklet (one full-page scan per page)")
    ap.add_argument("--list", default=None, metavar="FILE",
                    help="study list to check the names against "
                         "(default: weeds_list.txt in this project)")
    args = ap.parse_args()

    if not os.path.isfile(args.pdf):
        print(f"error: booklet not found: {args.pdf}")
        return 1
    if not args.dry_run:
        os.makedirs(OUT_BACK, exist_ok=True)
        os.makedirs(OUT_FRONT, exist_ok=True)

    doc = pymupdf.open(args.pdf)
    print(f"booklet: {doc.page_count} pages, deck: {len(DECK)} cards")
    if doc.page_count != len(DECK):
        print(f"warning: {doc.page_count} pages but {len(DECK)} deck entries")

    study_list = args.list
    if study_list is None:
        # The copy in the repo is the default so a fresh clone can still check
        # the names; the original outside the project is the fallback.
        study_list = STUDY_LIST if os.path.isfile(STUDY_LIST) else STUDY_LIST_OUTSIDE
    listed = parse_study_list(study_list)
    problems, tops = [], []

    for no, cid, name, sci, family in DECK:
        pno = no - 1                      # the pages are in study-list order
        im = page_scan(doc, pno)
        top = PHOTO_TOP.get(no) or frame_top(im)
        if top is None:
            problems.append(f"{no} {name}: no photo frame found - add a PHOTO_TOP entry")
            continue
        tops.append(top)
        paint = paint_line(im, top, no)
        frac = paint / im.height
        flag = ""
        if not 0.12 < frac < 0.22:
            flag = "  <-- check this page"
            problems.append(f"{no} {name}: paint line at {frac:.3f} of the page")
        if paint - top > 100:
            flag = "  <-- check this page"
            problems.append(f"{no} {name}: family word sits {paint - top} px "
                            "below the photo top")

        if not args.dry_run:
            front = im.copy()
            ImageDraw.Draw(front).rectangle([0, 0, im.width, paint - 1], fill="white")
            downscale(im, os.path.join(OUT_BACK, f"{cid}.jpg"))
            downscale(front, os.path.join(OUT_FRONT, f"{cid}.jpg"))

        # The study list is the examiner's own names - keep the two in step.
        note = ""
        if listed and no in listed:
            l_sci, l_common = listed[no]
            if l_sci.lower().replace("'", "") != sci.lower().replace("'", ""):
                note = f"  [study list says {l_sci}]"
                problems.append(f"{no} {name}: scientific name differs from weeds_list.txt")
        extra = "" if paint == top else f" paint={paint}"
        print(f"OK   {no:>2} {name:<28} {family:<15} top={top:<5} "
              f"({frac:.3f}){extra}{flag}{note}")

    if tops:
        med = sorted(tops)[len(tops) // 2]
        print(f"\nphoto top: median {med} px, range {min(tops)}-{max(tops)} px")

    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  - " + p)

    if args.dart or args.splice or not args.dry_run:
        if args.splice and not args.dry_run:
            splice_main()
        else:
            snippet = dart_snippet()
            if args.dart:
                with open(args.dart, "w", encoding="utf-8") as fh:
                    fh.write(snippet)
                print(f"\nwrote dart deck snippet -> {args.dart}")
            if not args.dry_run:
                print("\n--- kDeck / kFamilies (use --splice to write these "
                      "into lib/main.dart) ---")
                print(snippet)

    return 1 if problems else 0


def dart_deck_block():
    """The kDeck source for lib/main.dart, straight from DECK."""
    lines = ["const List<FlashCard> kDeck = <FlashCard>["]
    for no, cid, name, sci, family in DECK:
        esc = {s: s.replace("'", "\\'") for s in (name, sci, family)}
        lines.append(
            f"  FlashCard(id: '{cid}', title: '{esc[name]}', number: {no}, "
            f"sci: '{esc[sci]}', family: '{esc[family]}'),"
        )
    lines.append("];")
    return "\n".join(lines)


def dart_families_block():
    """The kFamilies map: family -> what it is called in plain words."""
    lines = ["const Map<String, String> kFamilies = <String, String>{"]
    for family in family_order():
        lines.append(f"  '{family}': '{FAMILY_COMMON[family]}',")
    lines.append("};")
    return "\n".join(lines)


def dart_snippet():
    return dart_deck_block() + "\n\n" + dart_families_block() + "\n"


def splice_main():
    """Rewrite the kDeck / kFamilies blocks inside lib/main.dart in place.

    Only those two blocks are touched; the rest of the file (including a
    hand-written deck, if someone edited one) stays as it is, so the builder
    stays the single source of truth for the deck instead of a list you have
    to copy-paste and hope matches.
    """
    text = open(MAIN_DART, encoding="utf-8").read()
    # lambda replacements: the Dart text contains \' escapes (Paddy's Lucern)
    # and a plain replacement string would be read as a regex template.
    deck = re.sub(r"(?ms)^const List<FlashCard> kDeck = <FlashCard>\[.*?^\];",
                  lambda m: dart_deck_block(), text, count=1)
    fams = re.sub(
        r"(?ms)^const Map<String, String> kFamilies = <String, String>\{.*?^\};",
        lambda m: dart_families_block(), deck, count=1)
    if fams == deck and deck == text:
        print("lib/main.dart: kDeck and kFamilies already up to date")
        return
    if fams == text:
        sys.exit("splice: could not find the kDeck / kFamilies blocks in "
                 f"{MAIN_DART} - they must start at column 0")
    with open(MAIN_DART, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(fams)
    print(f"lib/main.dart: rewrote kDeck ({len(DECK)} cards) and kFamilies "
          f"({len(family_order())} families)")


def family_order():
    """Families in booklet order, each named once."""
    seen = []
    for _no, _cid, _name, _sci, family in DECK:
        if family not in seen:
            seen.append(family)
    missing = [f for f in seen if f not in FAMILY_COMMON]
    if missing:
        sys.exit(f"FAMILY_COMMON has no common name for: {', '.join(missing)}")
    return seen



if __name__ == "__main__":
    sys.exit(main())
