# Dungeon Crawl Stone Soup — iOS (console build)

An iOS port of [Dungeon Crawl Stone Soup](https://github.com/crawl/crawl) (DCSS),
the open-source roguelike. This is the **ASCII / console** build: it renders the
game as a text grid (like the terminal version) rather than graphical tiles.

> **Not on the App Store — by the developers' choice.** DCSS is licensed under the
> GNU GPL v2+, whose freedoms (to copy, modify, and redistribute) are incompatible
> with the App Store's terms and DRM, and the DCSS developers enforce the license
> rather than relicense the game to fit the store (the same reason VLC and other
> GPL software aren't distributed there). So this is a **sideload** project: you
> build it yourself in Xcode and run it on your own device with a free Apple ID.
> There's nothing to purchase and no account to make beyond your existing Apple ID.

The console build was chosen deliberately for the simplest possible setup: it pulls
in **no SDL, no OpenGL/Metal, and no tile atlases**. The engine is stock upstream
DCSS plus a three-file shim (see [How it works](#how-it-works--the-shim) and
[UPDATING.md](UPDATING.md)).

---

## Requirements

- **macOS** with **Xcode 26 or newer** (developed on Xcode 26.5).
- An **iOS 18+** iPhone or iPad. (The simulator works too, for trying it out.)
- A **free Apple ID** — no paid Apple Developer Program membership required.
- `git`. **That's it** — no Python, Homebrew, CocoaPods, or command-line build
  steps. All generated engine source is committed, so there is no prebuild.

---

## Sideloading: build & run

Sideloading means installing an app you built yourself, signed with your own Apple
ID, straight onto your device — no App Store, no TestFlight. Here's the whole loop.

### 1. Clone — recursively

This repo doesn't contain the engine source directly — it *points* at it. The
DCSS engine lives in `Libraries/crawl` as a **git submodule** (a pinned reference
to a commit in a separate repo), and DCSS in turn pulls its own C dependencies —
**lua, sqlite, and pcre** — as further submodules nested inside it. A submodule
reference is just a recorded URL and commit; it holds no code on its own.

So a plain `git clone` gives you the app project with **empty** `Libraries/crawl`
and dependency folders, and the build fails with missing-file / missing-header
errors. `--recurse-submodules` walks that tree and actually fetches the engine and
its dependencies at the exact commits this project is pinned to:

```sh
git clone --recurse-submodules https://github.com/sethhoward/crawl-ios.git
cd crawl-ios
```

Already cloned without `--recurse-submodules` (empty submodule folders)? Fetch them
after the fact — `--recursive` reaches the nested dependencies too:

```sh
git submodule update --init --recursive
```

### 2. Open the project

```sh
open dcss.xcodeproj
```

### 3. Set your signing

Free Apple IDs can only sign apps under your own team and a unique bundle ID:

1. Select the **dcss** target → **Signing & Capabilities**.
2. **Team:** pick your personal team (add your Apple ID under *Xcode → Settings →
   Accounts* if it isn't listed).
3. **Bundle Identifier:** change it to something unique to you, e.g.
   `com.yourname.dcss`. (The repo ships `com.sandoze.dcss`, which only the original
   author can sign.)
4. Leave **Automatically manage signing** checked.

### 4. Build & run

1. Pick your device (or a simulator) and the **`dcss debug`** scheme.
2. Press **⌘R**.

First launch on a physical device: iOS will refuse to open an app from an
untrusted developer. Go to **Settings → General → VPN & Device Management**, tap
your developer certificate, and **Trust** it. Then launch the app again.

### The free-account catch: 7-day expiry

Apps signed with a free Apple ID **stop launching after 7 days** and must be
re-installed (rebuild & run from Xcode) to keep playing. A paid Apple Developer
account raises this to a year. Your **save files persist** across re-installs, and
the app auto-saves when it's backgrounded, so you won't lose a run to the expiry.

---

## Controls

The console build is keyboard-driven — the same key commands as terminal DCSS — so
the touch layer's whole job is to make those keystrokes reachable without a hardware
keyboard. A **hardware / Bluetooth keyboard also works** and is the most comfortable
way to play; everything below is the on-screen fallback.

The UI is **context-aware** — it changes with what the engine is doing (title screen
vs. in a dungeon vs. a menu/prompt) and with device **orientation**.

**On the title / menu screens**
- A bottom **control strip** with **Esc**, **Tab**, **↑ / ↓**, and **Enter** to
  navigate and confirm.

**In the dungeon**
- A faint **3×3 D-pad** overlaid on the map for the eight movement directions and
  wait (center). It fades after use and reappears when you touch it.
- An **assignable command bar** of game actions (see below).
- An **Esc** button anchored up beside the notch / Dynamic Island.
- **Swipe up** on the command bar to raise the iOS **software keyboard** for any key
  the on-screen controls don't cover (item letters, prompts, uncommon commands).

**When a menu, prompt, or targeting overlay is open**
- The command bar is replaced by a **navigation cluster**: **PgUp / PgDn**, the four
  **arrows**, and **Enter**. The map/menu scrolls freely underneath.

### The assignable command bar

Instead of memorizing which button does what, you **assign your own**:

- **Tap** a slot to fire its command. **Long-press** (or tap an empty **`+`** slot)
  opens a categorized menu — Extended Movement, Autofight, Item Interaction, etc. —
  mirroring DCSS's own in-game keyhelp. Pick a command and it's bound to that slot.
- Loadouts are **saved per orientation** (portrait and landscape keep separate sets)
  and persist across launches.
- **Portrait:** two rows at the bottom; **swipe up** once to reveal a third row of
  less-used actions, again to raise the keyboard, down to collapse.
- **Landscape:** a translucent column of buttons floats over the right edge of the
  map, out of the way of the view.

> The default loadout (Autofight, Explore, Travel, Fire) is provisional and will be
> tuned after more playtesting.

---

## How it works — the shim

The design goal is to run **stock upstream DCSS** with the thinnest possible iOS
layer, so tracking new releases stays cheap. There are two pieces: three tiny
patches inside the engine, and a self-contained bridge in `dcss/console/`.

**In the engine (three `#if defined(DCSS_IOS)` patches).** DCSS is a desktop program
that owns `main()` and calls `exit()`; iOS apps may do neither. The patches rename
`main()` so the app owns `UIApplicationMain`, loop the game forever instead of
terminating, turn a clean menu-quit into an in-app abort (re-showing the menu rather
than killing the process), and add a portrait "stacked" layout. That's the entire
engine delta — everything else is verbatim upstream. See [UPDATING.md](UPDATING.md).

**The bridge (`dcss/console/`).** This is where the shim earns its keep:

- **It plugs into an interface the engine already defines.** DCSS abstracts its
  terminal behind a *console backend contract* (`libconsole.h` / `cio.h`) — the same
  seam it uses for ncurses and the Windows console. `libios.mm` is just another
  implementation of that contract: a character-grid model plus an input queue, with
  the engine blocking in `getch_ck` for the next key. We're not forking rendering
  logic; we're implementing a port that upstream's architecture already anticipates.

- **It draws a clean C boundary between C++ and Swift.** `console_bridge.h` is
  **pure C** (no C++ types), so it drops straight into the Swift bridging header. The
  C++ engine never has to know Swift exists, and Swift never has to compile C++. The
  contract between them is a couple dozen flat C functions: read a cell, push a key,
  query "is a menu open?", request a save.

- **It runs the engine and the UI on separate threads, safely.** The engine runs on
  its own thread and blocks on the input queue; SwiftUI runs on the main thread,
  snapshots the mutex-guarded cell grid to draw, and pushes keystrokes in. A redraw
  callback nudges the UI. State-hazardous operations (like saving) are deferred to
  the engine thread at a safe input boundary rather than done from the UI thread.

- **It surfaces engine data instead of duplicating it.** The command bar's catalog is
  built by reading the engine's own `command_type` table through the bridge
  (`command_to_key`, `command_to_name`) — so the buttons send whatever keystroke the
  engine currently maps a command to, with no second copy of the keymap to drift out
  of sync.

**Is the shim a good bridge? Yes** — because it bridges along a seam the engine
already has, keeps C++ and Swift on their own sides of a flat C interface, and adds
no rendering or game logic of its own. That's exactly what keeps the port to ~three
patched engine files and a version-independent `dcss/console/` layer: bumping DCSS is
mostly re-applying three small patches and reconciling the Xcode file list, not
re-integrating a UI. The one real coupling risk is if upstream changes the
`libconsole.h` / `cio.h` signatures — and the linker flags that immediately.

---

## What's left to do

This is a working, playable port, but it isn't finished. Known gaps and next steps:

- **Tap-to-travel.** Touching a map tile to walk/travel there is not wired up; the
  console build is keyboard-first for now. This is the biggest missing touch
  affordance.
- **Finalize the default button-bar loadout** after more playtesting (current seed is
  provisional).
- **Sound.** The console build links no audio; there is no sound.
- **App Store distribution** isn't an option — the GPL is incompatible with the
  store's terms and the DCSS developers enforce it (see the note at the top), so
  sideloading is the only path, with the 7-day free-account expiry.
- **Maintainer ergonomics.** Reconciling the Xcode source list on a version bump is
  still manual; scripting the `Makefile.obj → project.pbxproj` diff (noted in
  [UPDATING.md](UPDATING.md)) would make future bumps close to one command.

---

## Updating the engine / for maintainers

The whole point of the console design is that bumping DCSS to a new release is
cheap. The architecture and the step-by-step version-bump workflow are documented
in **[UPDATING.md](UPDATING.md)**.

---

## Credits & license

This project as a whole is licensed under the **GNU GPL v2+** — see
[LICENSE](LICENSE) for the full text and what it covers.

- **Dungeon Crawl Stone Soup** is by the DCSS dev team and contributors, released
  under the GNU GPL v2+. The engine submodule (`Libraries/crawl`) carries its own
  `LICENSE` and `crawl-ref/CREDITS.txt` with the per-file license details and full
  contributor credits.
- The iOS integration layer (`dcss/app/`, `dcss/console/`) and this packaging build
  on the earlier iOS port work by [apollovy](https://github.com/apollovy/crawl-ios),
  and are likewise GPL v2+.
