# Weed ID Trainer

Swipe flashcards for **weed identification** - 45 cards made from the revised
weed booklet. Study for exams: each card is a page with its name band painted
out; flip it to check.

Works on phones, tablets and computers - mouse or touch.

## Download and install

Pick whichever one suits you. Nothing needs an account, and the deck is the
same in all three.

### 1. Play online - nothing to install

**https://s4me4su.github.io/weed-flashcards/**

- Works in any modern browser (Chrome, Edge, Safari, Firefox).
- Opens in a few seconds; each card's picture is cached as you reach it, so
  after a pass through the deck it opens fast, even offline.
- On an iPhone, **Share -> Add to Home Screen** gives it an app icon and a
  full-screen launch - that is the only way to get it on an iPhone.

### 2. Android app - download the APK

Get **Weed-ID-Trainer-1.0.0+1.apk** from the
[Releases page](https://github.com/s4me4su/weed-flashcards/releases) and
install it:

1. Tap the APK download.
2. Android warns about "unknown sources" / "not verified by Play Protect" -
   that is normal for any app installed outside the Play Store. Choose
   **Allow** / **Install anyway**.
3. Open **Weed ID Trainer** from your app drawer.

`Weed-ID-Trainer-1.0.0+1.apk` works on every Android phone. The
`...-arm64-v8a.apk` next to it is about half the size and fits most phones
bought in the last few years - if it refuses to install, use the other one.
A newer APK installs over the old one and keeps your saved deck.

### 3. Windows app - download the ZIP

Get **Weed-ID-Trainer-Windows-1.0.0.zip** from the same
[Releases page](https://github.com/s4me4su/weed-flashcards/releases):

1. Download it, then right-click the zip and choose **Extract All**.
2. Open the extracted folder and run **weeds_flashcards.exe** - worth making a
   desktop shortcut from it (right-click -> Send to -> Desktop).

No installer and no administrator rights needed. Your progress is saved in a
`weeds_deck_v1.json` file next to the exe, so keep the folder.

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
- Saves live on your own device - in the browser for the web version, in the
  app's folder for the Windows version, in the app's storage on Android. They
  never leave your device.
- Clearing browser data resets web progress.

## One known slip

Page 31 (Catsear / Flatweed) has a herbarium label *inside* the photograph, so
that front card still names the plant. Everything else is clean.

## Where the cards come from

Scanned from the 45-page revised weed booklet. `tools/build_weed_cards.py` in
the source finds the top edge of the photo frame on every page and paints the
name band out, so the fronts are the real pages rather than cropped or blurred
copies. Built with Flutter - the web app, the Android APK and the Windows app
are all built from one codebase:
https://github.com/s4me4su/weed-flashcards/tree/main
