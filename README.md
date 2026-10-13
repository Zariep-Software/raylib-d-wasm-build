# raylib-d WASM build script

This is a template for building a raylib-d game for web/wasm (emscripten).

## Requirements

- Linux with LDC (Not tested on Windows/MacOS)
- [emsdk](https://emscripten.org/docs/getting_started/downloads.html), `emcc` must be reachable (on `PATH`, or via `EMSDK_DIR`)
- A [Raylib](https://github.com/raysan5/raylib) `.a` file compiled for WASM
- `raylib-d` (either a `raylib/` folder inside your sources, or as a `dub.json` dependency)
- `dmd` or `ldc2` on your host, to run `build_web.d` itself via `rdmd`/`dmd -run`

## Prepare

### Get Raylib

Two paths:

#### Option 1:  Prebuild
download the webassembly zip from the [raylib releases](https://github.com/raysan5/raylib/releases) and take
`libraylib.web.a` from it.

#### Option 2: Build it

```
git clone https://github.com/raysan5/raylib
cd raylib/src
source /path/to/emsdk/emsdk_env.sh
make PLATFORM=PLATFORM_WEB -B
```

Then place the library anywhere you like, for example:

```
-> tree raylib-web/
raylib-web/
└── lib
    └── libraylib.web.a
```

> The script looks for `libraylib.web.a` first, then `libraylib.a`.

### Make raylib-d importable

The script finds the raylib-d import path in this order:

1. `RAYLIB_D_IMPORT`, if set
2. `<source dir>/raylib`, if that folder exists (raylib-d copied into your sources)
3. `dub describe`, so add `raylib-d` to your `dub.json` dependencies

### Define the configuration

Edit `websetup.sh`. `build_web.d` loads simple `KEY=VALUE` lines from it
automatically if the file exists, and expands `$VAR`, `${VAR}`, and a
leading `~` (e.g. `$USER`, `$HOME`) the same way a shell would.
It is parsed, not executed, so there is no shell logic in there.

```
# REQUIRED
RAYLIB_WEB_LIB_DIR=~/libs/raylib-web/lib

# Optional
EMSDK_DIR=~/emsdk
WEB_SHELL_PATH=web/custom_shell.html
WEB_CSS_PATH=web/style.css
```

Variables set in your real environment work too, `websetup.sh` only
overrides the ones it defines.

| Variable | Default | Description |
| --- | --- | --- |
| `RAYLIB_WEB_LIB_DIR` | *(required)* | Directory containing `libraylib.web.a` or `libraylib.a` |
| `EMSDK_DIR` | | emsdk root, its `upstream/emscripten` is added to `PATH` |
| `RAYLIB_D_IMPORT` | auto | raylib-d import path (see above) |
| `WEB_SOURCE_DIR` | `source`, `src` or `.` | Where your `.d` files are |
| `WEB_ASSETS_DIR` | `assets` | Preloaded into the build; skipped if missing or empty |
| `WEB_OUTPUT_DIR` | `web` | Where `index.html`, `.js`, `.wasm` and `.data` go |
| `WEB_SHELL_PATH` | built-in | Custom HTML shell |
| `WEB_CSS_PATH` | built-in | Custom CSS |
| `INITIAL_MEMORY` | `67108864` | Initial wasm memory in bytes |
| `EXTRA_CFLAGS` / `EXTRA_LDFLAGS` | | Extra flags, each token is passed to emcc via `--Xcc=` |
| `EXTRA_DFLAGS` | | Extra raw `ldc2` flags (extra `.o`/`.a`, `-version=Foo`...) |


## Custom HTML / CSS

If you set nothing, a built-in shell with a spinner is used.

**Custom HTML:** point `WEB_SHELL_PATH` to your own file. It must contain the
emscripten placeholder `{{{ SCRIPT }}}`, and a `<canvas id="canvas">`.

**Custom CSS:** point `WEB_CSS_PATH` to a `.css` file. It is merged into the shell:

- if the shell contains the marker `/* WEB_CSS */`, the CSS replaces it
- otherwise it is injected as a `<style>` block right before `</head>`

You can use only the CSS (keeping the built-in HTML), only the HTML, or both.
Note that the built-in CSS is replaced, not extended, once you provide your own.

The merged shell is generated in a temp folder on every build, so your
`web/` folder does not get a stray `shell.html`.


## Try to build

The build helper is a native D script (`build_web.d`), no shell interpreter required beyond your normal system tools (`ldc2`, `emcc`, `emrun`).

Run it with `rdmd` (bundled with DMD/LDC) or compile it once and reuse the binary:

```shell
rdmd build_web.d            # debug build, then opens it with emrun
rdmd build_web.d -release   # -release -O2
rdmd build_web.d -build     # build only, do not launch emrun
rdmd build_web.d -betterc -release -build
```

Equivalent, using `dmd`/`ldc` directly instead of `rdmd`:

```shell
dmd -run build_web.d -release -build
```

| Flag | Description |
| --- | --- |
| `-betterc` | Use the `-betterC` flag (with `--checkaction=halt`) |
| `-release` | Use `-release -O2` instead of the debug flags |
| `-build` | Avoid `emrun` after a successful build |

The result is `web/index.html` (plus its `.js`, `.wasm` and `.data`).
Browsers will not load wasm from `file://`, serve the folder with `emrun`
or `python3 -m http.server -d web`.


## Hooks

Both hooks are plain, standalone, optional shell scripts: they are executed,
not sourced. If a file is missing the hook is silently skipped. If it exists
but is not executable, the build warns and skips it (`chmod +x` it).

### `webprebuild.sh`

Runs before compiling.

```
./webprebuild.sh <outputDir> <libPath> <sourceDir> <assetsDir>
```

Environment: `WEB_OUTPUT_DIR`, `WEB_LIB_PATH`, `WEB_SOURCE_DIR`,
`WEB_ASSETS_DIR`, `WEB_SHELL_FILE`, `BUILD_MODE` (`debug` or `release`).

Any stdout line of the form `EXTRA_CFLAGS=...`, `EXTRA_LDFLAGS=...` or
`EXTRA_DFLAGS=...` is collected and appended to the matching flag set.
Handy for compiling extra C sources with `emcc` and linking them in:

```sh
emcc -c native/helper.c -o "$1/helper.o" -DPLATFORM_WEB
echo "EXTRA_DFLAGS=$1/helper.o"
```

### `webpostbuild.sh`

Runs after a successful build.

```
./webpostbuild.sh <pathToIndexHtml>
```

Environment: `WEB_OUTPUT_DIR`, `BUILD_MODE`. Handy for zipping the output
for itch.io, hashing files, copying to a server folder, etc.
Its `EXTRA_*` lines (if any) are ignored since the build already ran;
only side effects and the exit status matter (a non-zero exit fails the build).


## Use it as a submodule

This project can be used as submodule:

```
git submodule add <this-repo-url> wbuild
```

so then you call

```
rdmd wbuild/build_web.d -release -build
```

> The config and hooks (`websetup.sh`, `webprebuild.sh`, `webpostbuild.sh`)
> are looked up in the **current directory**, so run the command from your
> project root and keep your own copies there.


## Troubleshooting

- **`Set RAYLIB_WEB_LIB_DIR`**: the variable is missing, check `websetup.sh` is in the directory you run the script from.
- **`Missing libraylib(.web).a`**: the folder exists but has neither file, use the wasm build of raylib, not a desktop one.
- **`Could not find raylib-d import path`**: set `RAYLIB_D_IMPORT`, or add `raylib-d` to `dub.json`.
- **`emcc` not found**: source `emsdk_env.sh` or set `EMSDK_DIR`.
- **Blank page / wasm fails to load**: serve over HTTP instead of opening `index.html` directly.
- **emcc complains about the preload folder**: the script already skips empty/missing asset folders, check `WEB_ASSETS_DIR`.