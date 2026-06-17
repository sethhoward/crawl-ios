# Updating DCSS (engine submodule)

This is an iOS **ASCII/console** port of Dungeon Crawl Stone Soup. The design keeps
the engine as close to upstream as possible so version bumps stay cheap:

- `Libraries/crawl` is a submodule pointing at **`sethhoward/crawl`** (a fork of the
  official **`crawl/crawl`**), branch `console-<version>`.
- That branch is **upstream's release tag + exactly one patched file** (`main.cc`):
  rename `main()` → `DCSS_main` under `DCSS_IOS` (so the app owns `UIApplicationMain`)
  and guard a `system()` call that's unavailable on iOS. See commit
  `iOS console entry: DCSS_main under DCSS_IOS + guard system()`.
- The whole iOS layer is in **`dcss/console/`** and is version-independent:
  - `libios.mm` — implements DCSS's console backend contract (`libconsole.h`):
    a character-grid model + input queue (`getch_ck` blocks on it).
  - `ConsoleView.mm` — UIKit text-grid renderer (Menlo, 16-colour DCSS palette).
  - `ConsoleAppDelegate.mm` — non-SDL app shell + on-screen control bar; reuses
    `CDDA_iOS_main.mm` to build argv and call `DCSS_main`.
- No SDL / SDL_image / SDL_mixer / freetype, no tile atlases, no Metal toolchain.

The console build compiles crawl's base (non-tiles) source set **plus** the tiledef
*index tables* (`rltiles/tiledef-*.cc`) — core map/save code references the tile
enums even in console — but **not** the tile atlas PNGs.

---

## Steps to bump to a new DCSS release (e.g. 0.35.0)

### 1. Re-apply the shim onto the new tag (minutes)
In a clone of `sethhoward/crawl`:
```sh
git remote add upstream https://github.com/crawl/crawl.git   # once
git fetch upstream --tags
git checkout -b console-0.35.0 0.35.0
git cherry-pick <main.cc shim commit>      # or: git rebase --onto 0.35.0 0.34.1 console-0.34.1
git push -u origin console-0.35.0
```
It's one small hunk — expect a clean apply or a trivial context fixup.

### 2. Regenerate the generated build inputs (macOS prebuild)
Crawl generates several build inputs (gitignored): the tiledef tables, `prebuilt/levcomp.*`,
and YAML-derived headers (`mon-data.h`, `species-data.h`, `job-data.h`, …).
```sh
cd Libraries/crawl/crawl-ref/source
python3 -m venv /tmp/crawlbuild-venv && /tmp/crawlbuild-venv/bin/pip install pyyaml
make TILES=1 mac-app-tiles PYTHON=/tmp/crawlbuild-venv/bin/python
```
Quirk: `contrib/Makefile` computes its install prefix via `realpath` of a not-yet-existing
dir → empty → tries to install to `/`. Pre-create it and symlink:
```sh
ARCH=$(cc -dumpmachine)
mkdir -p install/$ARCH/{include,lib}
ln -sfn ../install contrib/install
ln -sfn source/install ../install   # i.e. crawl-ref/install -> source/install (for depth-2 deps like lua)
```

### 3. Reconcile the Xcode source list (the main recurring chore)
DCSS adds/removes/renames `.cc` files between versions; `dcss.xcodeproj` lists them
explicitly. Diff the console object set and update the project's Sources phase:
```sh
git -C Libraries/crawl diff 0.34.1:crawl-ref/source/Makefile.obj \
                            console-0.35.0:crawl-ref/source/Makefile.obj
```
Add new files / remove gone files in `dcss.xcodeproj/project.pbxproj` (each needs a
PBXFileReference + PBXBuildFile + group entry + Sources-phase entry). Also re-check the
lua contrib file list (`contrib/lua/src/*.c`) for adds/removes. For a minor release this
is usually only a handful of files. Run `plutil -lint dcss.xcodeproj/project.pbxproj`
after editing.

### 4. Build, fix, repoint
```sh
xcodebuild -project dcss.xcodeproj -scheme "dcss debug" \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```
Fix any minor C++/API breakage, then update the submodule pointer + `.gitmodules`
branch to `console-0.35.0` and commit in this repo.

---

## What to watch for

- **The one real risk:** if upstream changes the `libconsole.h` / `cio.h` **backend
  contract** (a function signature), `libios.mm` needs a matching change. The linker
  flags it immediately (undefined or unused symbol). Rare across a minor release; quick fix.
- **Grid minimum:** DCSS stalls before drawing if the grid is under ~80×24. `ConsoleView`
  sizes the font to guarantee ≥24 rows (landscape is wide-but-short, so rows bind first).
- Everything else (renderer, input, app shell, the `main.cc` shim) carries forward untouched.

## Optional: make future bumps even cheaper
- **Commit the generated build inputs** (tiledef tables, `levcomp.*`, YAML data headers)
  to the `console-<version>` branch so a clean clone builds without the prebuild. Commit
  only the deterministic, data-derived files — **not** machine/build-specific ones
  (`config.h`, `build.h`, `compflag.h`).
- **Script step 3** (Makefile.obj diff → pbxproj patch) so the file-list reconciliation
  is one command.
