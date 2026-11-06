# Weed ID Trainer

Swipe flashcards for weed identification, built from the scanned profile
booklet (`C:\weeds\weeds_revised_001.pdf`): 45 pages, one weed per page, shown
**nameless first** and named when you flip. Runs on **Windows 11 (touch screen),
Android and any phone browser**.

| Platform | How friends get it | Cost |
|---|---|---|
| Windows 11 | `.\build_windows.ps1` -> zip up `dist\Weed-ID-Trainer-Windows-1.0.0.zip` | free |
| iPhone / any phone | <https://s4me4su.github.io/weed-flashcards/> (`.\publish_web.ps1`) | free hosting |
| Android | `flutter build apk` (no signing key set up yet - see *Android*) | free (no Play Store) |

The PowerShell scripts need `powershell -NoProfile -ExecutionPolicy Bypass -File .\build_web.ps1`
unless you allow scripts once with `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## How it works

- **Front of card** (the side you see first): the booklet page with its header
  band painted white - `assets/front/<id>.jpg`. The band is where the common
  name, scientific name and plant family are printed, so painting it out hides
  all three; you are left with the photos.
- **Back of card**: the same page exactly as printed - `assets/back/<id>.jpg`.
  Nothing is drawn over it, the answer is the page itself.
- **Tap** the card to flip it 180°. **Swipe/drag** left = "REVIEW",
  right = "KNOWN". Arrow keys swipe and space flips on the desktop.
- Top bar shows progress ("Card 3 of 45"), the **plant family filter**
  (All weeds + the 27 families printed in the booklet) and **Save** /
  **Reset / Reshuffle** buttons.
- The family is never printed as a label anywhere on the front, or on the card
  back's overlay - it only appears in the filter, in the summary at the end of
  the deck, and inside the back image. Otherwise the dropdown would hand you
  the answer.
- The deck (45 cards) is the explicit `kDeck` list in `lib/main.dart`; each
  entry's `id` pairs the two images 1:1, and `number` is the page number in the
  booklet (page N = card N = line N of `weeds_list.txt`).
- Your position, review marks, the family filter and removed cards are saved
  automatically (a moment after any change, and whenever the app is closed or
  backgrounded): `weeds_deck_v1.json` **next to the .exe** on Windows, so the
  whole folder can be carried on a USB stick with the progress inside it (the
  temp folder is used only if the install location is read-only), the app's
  `files` directory on Android (never the cache dir, which Android can purge),
  and `localStorage` key `weeds_deck_v1` on the web - see `lib/storage*.dart`.
  The Save button's tooltip shows the exact path.

## Rebuilding the cards from the booklet

`tools/build_weed_cards.py` is the source of truth for both the images and the
Dart deck. Each PDF page is one full-page JPEG scan, so a card *is* that page:
it finds the top edge of the first photo frame (a long dark run that also runs
down at both ends, which is what tells a photo frame from the header's
underline), paints everything above it white for the front, and writes both at
1000 px / quality 86.

```powershell
python tools\build_weed_cards.py                 # 90 images + report
python tools\build_weed_cards.py --dry-run       # report, write nothing
python tools\build_weed_cards.py --splice        # also rewrite kDeck / kFamilies
                                                 # in lib/main.dart
python tools\build_weed_cards.py --dart out.dart # Dart source to a file instead
```

Two guards worth knowing about:

- If the printed family word sits *below* the photo frame's top edge (page 44,
  Winter Grass), the paint line is pushed down to cover it, and the report says
  `paint=`. A page that needs more than 100 px of push is flagged.
- If detection ever fails on a page, `PHOTO_TOP = {page: y}` in that file pins
  the line by hand, in native scan pixels (the scan is 1240 px wide, the asset
  1000 px, so multiply by 1.24). It is empty right now.

The builder also cross-checks every name against the study list (`weeds_list.txt`
in this project, a copy of the examiner's list; `--list FILE` or the original at
`C:\weeds\weeds_list.txt` overrides it) and exits non-zero if the booklet and the
list disagree.

```powershell
python tools\check_deck.py      # deck <-> images: no card without images,
                                # no image without a card, numbers 1..45,
                                # every family present in kFamilies
python tools\gen_icons.py       # redraw launcher/PWA/Windows icons from one design
```

Images are 20.3 MB in 90 files (45 fronts + 45 backs). The source PDF is not in
this repo, so the images are: the app builds without the booklet.

## Web (works on iPhones)

**Live: <https://s4me4su.github.io/weed-flashcards/>** - hosted by GitHub Pages
from the `gh-pages` branch of this repo.

```powershell
.\publish_web.ps1                # build for /weed-flashcards/ + push gh-pages
.\publish_web.ps1 -NoBuild       # push whatever build\web holds right now
```

Or to build without publishing (a different host, or to try it locally):

```powershell
.\build_web.ps1                    # -> build\web, for a site root
.\build_web.ps1 -BaseHref /weed-flashcards/   # GitHub Pages project site
.\build_web.ps1 -Serve             # preview at http://127.0.0.1:8899
.\build_web.ps1 -Zip               # dist\weeds-web.zip for drag-and-drop hosts
```

`publish_web.ps1` turns `build\web` into a single parentless `gh-pages` commit
and force-pushes it, so the served build never accumulates history in the repo.
The branch is enabled as the Pages source once, with:

```powershell
gh api -X POST repos/s4me4su/weed-flashcards/pages -f source[branch]=gh-pages -f source[path]=/
```

Upload the contents of `build\web` to any other static host - Netlify Drop,
Cloudflare Pages are free. On an iPhone, **Share -> Add to Home Screen** gives
it an app icon and full-screen launch.

Images are fetched one card at a time (and the next card is pre-cached while you
are still looking at this one), so the first card shows up quickly even though
the deck is 20 MB.

`--no-web-resources-cdn` keeps CanvasKit and the fallback font inside
`build\web`, so the page never contacts Google's CDN, and
`web\app_service_worker.js` caches what the friend has already seen: after the
first visit the app opens with no network at all (the shell is served
network-first so a new deploy is never hidden, card images cache-first).
`build_web.ps1` stamps a build version into that file on every build, checks all
90 images are actually in the bundle, and drops ~20 MB of renderer copies a
dart2js build never loads (`-Full` keeps them).

## Run on Windows 11 (touch)

Requires Flutter (installed at `C:\flutter`) and Visual Studio 2022 Build Tools
with the "Desktop development with C++" workload.

```powershell
flutter run -d windows          # dev mode
flutter build windows           # -> build\windows\x64\runner\Release\
.\build_windows.ps1             # -> dist\Weed-ID-Trainer-Windows-1.0.0.zip
```

`build_windows.ps1` also checks the bundle is complete (exe,
`flutter_windows.dll`, `data\app.so`, `data\flutter_assets`, and 45 fronts + 45
backs) before zipping, so a build that would open with nothing but "Missing
asset" placeholders never gets sent out. Everything in that `Release` folder
belongs together; zip it and it runs with no install.

## Android

Not packaged yet: no signing key exists, and an APK you send to friends has to
be signed with a key you keep (a differently signed APK cannot be updated in
place - it would force them to uninstall and lose their saved deck). Until then
the web build is the phone route.

To build one, point Flutter at an Android SDK + JDK (`flutter doctor -v` should
show a green Android toolchain), then `flutter build apk --release`. The icons
in `android\app\src\main\res\mipmap-*` and the label ("Weed ID Trainer") are
already set.

## Tests

```powershell
flutter test
```

Twenty-one tests: the deck's own invariants (every card has both images, no
image is unused, 45 cards / 27 families, the family filter matches something),
plus a test that **no weed name, scientific name or family is ever printed on
screen** as text - only inside the back image. Then tap/swipe/keyboard,
remove-and-undo, the family dropdown, auto-save, restoring an older, filtered
or corrupt save file, and layouts that must not overflow - phone width 393x852
and a very short window.

## Notes

- No third-party packages at all - `pubspec.yaml` depends only on Flutter
  itself. The swipe + flip use `GestureDetector` + `Transform` +
  `AnimationController`, so finger touch and mouse drag behave identically, and
  the save file is plain `dart:io` / `localStorage`. Nothing is fetched at
  runtime: the Windows zip, the APK and the web build each carry everything.
- Missing images show a "Missing asset: ..." placeholder instead of crashing.
- **One known leak**: page 31 (Catsear / Flatweed) has a herbarium label
  *inside* the photo reading "Cistolina giuncolina", so that card's front still
  names the plant. Painting it out would mean painting over the specimen photo,
  so it is left alone.
- The scanned pages are crooked by a degree or two and the frame detector works
  on the unscaled scan; if you rescan the booklet at a different size, run
  `--dry-run` first and read the `top=` column before trusting the images.
