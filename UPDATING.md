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
Crawl generates several build inputs: the tiledef index tables, `prebuilt/levcomp.*`,
YAML-derived headers (`mon-data.h`, `species-data.h`, `job-data.h`, …), and
`config.h`/`build.h`/`compflag.h`. **These are committed on `console-<version>`** so a
clean clone builds without a prebuild (see "Generated files are committed" below) — but
when you move to a new release you must regenerate them and commit the new versions.
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

## Generated files are committed (why a clean clone builds)

To make the sideloader experience "clone → build", the generated build inputs are
**force-committed** on the `console-<version>` branch (they're in crawl's `.gitignore`,
so `git add -f`):

- Data-derived headers: `aptitudes.h`, `art-data.h`/`art-enum.h`, `cmd-name.h`,
  `form-data.h`, `mi-enum.h`, `mon-data.h`/`mon-mst.h`, `job-*.h`, `species-*.h`.
- Tiledef index tables: `rltiles/tiledef-{dngn,feat,floor,gui,icons,main,player,unrand,wall}.cc/.h`
  (console links the index tables, not the atlas PNGs). `prebuilt/levcomp.*` is already tracked.
- `config.h` (iOS feature detection — stable across Apple hosts) and `build.h`
  (version strings — correct for the pinned tag).
- `compflag.h` is **hand-written with neutral values**, not the prebuild's output: the
  prebuild emits the host triple + macOS-tiles flags, which are wrong here and machine-specific.
  It only feeds the version/crash display string in `version.cc`, so neutral text is fine.

**Not committed** (not compiled in console): atlas PNGs, `tileinfo-*.js`, `tile-feat.html`,
`status-icon-sizes.h`, `util/levcomp.*` backups.

**On a version bump:** regenerate (step 2), then re-`git add -f` the data headers + tiledef
tables + `config.h`/`build.h`, **regenerate `compflag.h` by hand** (don't commit the prebuild's
machine-specific version), and commit on the new branch.

## Optional: make future bumps even cheaper
- **Script step 3** (Makefile.obj diff → pbxproj patch) so the file-list reconciliation
  is one command.
