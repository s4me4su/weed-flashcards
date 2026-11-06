# Weed ID Trainer

Swipe flashcards for **weed identification** - 45 cards made from the revised
weed booklet. Study for exams: each card is a page with its name band painted
out; flip it to check.

Works on phones, tablets and computers - mouse or touch.

## Play online (no install)

**https://s4me4su.github.io/weed-flashcards/**

- Works in any modern browser (Chrome, Edge, Safari, Firefox).
- Opens in a few seconds; each card's picture is cached as you reach it, so
  after a pass through the deck it opens fast, even offline.
- Nothing to install, nothing to sign up for.
- iPhone: **Share -> Add to Home Screen** gives it an app icon and a
  full-screen launch.

## How to use

Each card has two sides:

- **Front** - the booklet page with its header band painted white, so the
  common name, scientific name and plant family are all hidden (exam mode)
- **Back** - the page exactly as printed

| Action | What it does |
|---|---|
| **Tap the card** | Flip it over |
| **Swipe right** (or green check) | "I know this one" |
| **Swipe left** (or red cross) | "Not sure" - marks it for review |
| **Trash icon** | Remove this card from the deck (undo offered) |
| **Filter dropdown** (top bar, "All weeds") | Study one plant family at a time |
| **Save icon** (top right) | Save progress - the app also saves automatically |
| **Reset icon** (top right) | Reset & reshuffle: full deck returns, removed cards come back |

When you finish the deck you get a summary of everything you marked **for
review**, grouped by plant family, so you can reshuffle and go straight at the
ones you keep getting wrong.

## About your progress

- Your position, removals and review marks are saved **automatically**.
- Saves live on your own device/browser - they never leave your device.
- Clearing browser data resets web progress.

## One known slip

Page 31 (Catsear / Flatweed) has a herbarium label *inside* the photograph, so
that front card still names the plant. Everything else is clean.

## Where the cards come from

Scanned from the 45-page revised weed booklet. `tools/build_weed_cards.py` in
the source repo finds the top edge of the photo frame on every page and paints
the name band out, so the fronts are the real pages rather than cropped or
blurred copies. Built with Flutter - a Windows app, a web app and an
Android-ready app from one codebase.

Source: https://github.com/s4me4su/weed-flashcards (the `main` branch)
