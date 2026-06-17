# Dungeon Crawl Stone Soup — iOS (console build)

An iOS port of [Dungeon Crawl Stone Soup](https://github.com/crawl/crawl) (DCSS),
the open-source roguelike. This is the **ASCII / console** build: it renders the
game as a text grid (like the terminal version) rather than graphical tiles.

> **Not on the App Store.** Apple does not permit DCSS on the App Store, so this
> is a **sideload** project: you build it yourself in Xcode and run it on your own
> device with a free Apple ID. There's nothing to purchase and no account to make
> beyond your existing Apple ID.

The console build was chosen deliberately for the simplest possible setup: it pulls
in **no SDL, no OpenGL/Metal, and no tile atlases**. The engine is stock upstream
DCSS plus a one-file entry-point shim (see [UPDATING.md](UPDATING.md)).

---

## Requirements

- **macOS** with **Xcode 26 or newer** (developed on Xcode 26.5).
- An **iOS 18+** iPhone or iPad. (The simulator works too, for trying it out.)
- A **free Apple ID** — no paid Apple Developer Program membership required.
- `git`. **That's it** — no Python, Homebrew, CocoaPods, or command-line build
  steps. All generated engine source is committed, so there is no prebuild.

---

## Build & run

### 1. Clone — recursively

The engine and its lua/sqlite/pcre dependencies are git submodules, so you must
clone with `--recurse-submodules`:

```sh
git clone --recurse-submodules https://github.com/sethhoward/crawl-ios.git
cd crawl-ios
```

Already cloned without `--recurse-submodules`? Run this once:

```sh
git submodule update --init --recursive
```

### 2. Open the project

```sh
open dcss.xcodeproj
```

(Open the **`.xcodeproj`**, not a workspace — there is no CocoaPods workspace.)

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

---

## Playing on a touch screen

The console build is keyboard-driven (the same key commands as terminal DCSS).
To make that workable without a hardware keyboard, the app shows an on-screen
**control bar** with the keys you can't easily type otherwise:

- **Esc**, **Tab**, **Enter**, and the four **arrow keys**.
- A **keyboard toggle** that brings up the iOS software keyboard for everything
  else (letters and command keys).

A hardware/Bluetooth keyboard also works and is the most comfortable way to play.

> Tap-to-travel (touching a map tile to walk there) is not wired up yet — the
> console build is keyboard-first for now.

---

## Free-account caveat

Apps signed with a free Apple ID **expire after 7 days** and must be re-installed
(rebuild & run from Xcode) to keep playing. A paid Apple Developer account raises
this to a year. Your **save files persist** across re-installs.

---

## Updating the engine / for maintainers

The whole point of the console design is that bumping DCSS to a new release is
cheap. The architecture and the step-by-step version-bump workflow are documented
in **[UPDATING.md](UPDATING.md)**.

---

## Credits & license

- **Dungeon Crawl Stone Soup** is by the DCSS dev team and contributors, released
  under the GNU GPL v2+. See the engine submodule (`Libraries/crawl`) for its
  full license and credits.
- The iOS integration layer (`dcss/console/`) and this packaging build on the
  earlier iOS port work by [apollovy](https://github.com/apollovy/crawl-ios).
