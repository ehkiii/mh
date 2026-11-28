# SealPad

A Seal-style yt-dlp downloader for iPad/iPhone: SwiftUI with Liquid Glass, embedded CPython, and in-app yt-dlp updates.

Untested scaffold: I couldn't run Xcode or the Python iOS toolchain in my sandbox, so the first CI run will probably need a fix or two. Download the `build-log` artifact from the failed run and send me the errors.

## Build with GitHub Actions
1. Push this folder to a GitHub repo (branch `main`).
2. The **Build IPA** workflow runs automatically. You can also run it by hand from the Actions tab.
3. When it finishes, download the **SealPad-ipa** artifact.
4. Tag a commit `v1.0` (`git tag v1.0 && git push --tags`) and the IPA is attached to a GitHub Release too.
5. Install the `.ipa` with AltStore, SideStore or Sideloadly. It's unsigned, and those tools sign it with your Apple ID.

The workflow:
- runs on `macos-26` with the latest stable Xcode (change the label to `macos-latest` if `macos-26` isn't available to you)
- downloads the official python.org iOS XCframework for Python 3.15 (the newest 3.15.x)
- installs yt-dlp, its exact pinned yt-dlp-ejs, and certifi from PyPI, and fails if any native modules sneak in
- generates the Xcode project from `project.yml` with XcodeGen, so there is no `.xcodeproj` to maintain
- builds, zips the app into `SealPad.ipa`, and uploads it

## Build locally (Mac with Xcode 26)
```bash
./scripts/bootstrap.sh     # Python runtime + packages + SealPad.xcodeproj
./scripts/build_ipa.sh     # produces SealPad.ipa
```
Or run only the bootstrap and open `SealPad.xcodeproj` in Xcode to run it on a device.

## Things to change
- **Bundle ID:** `PRODUCT_BUNDLE_IDENTIFIER` and `bundleIdPrefix` in `project.yml`.
- **Python version:** `PY_MINOR` in the workflow (or when running it manually). The Objective-C bridge reads the version from `Python.h`, so nothing else needs to match.

## Layout
- `Swift/`: SwiftUI app, download manager, and the Python call wrapper
- `ObjC/`: the CPython embedding bridge and the bridging header
- `app/bridge.py`: the Python side (info, downloads, events, updater)
- `scripts/`: bootstrap and build scripts
- `project.yml`: the XcodeGen project spec (Info.plist keys, build settings and the "Process Python libraries" step live here)

Downloads land in **Files › On My iPad › SealPad › Downloads**.

## Known gaps (next steps)
1. **YouTube JS challenges.** yt-dlp needs a JS runtime plus yt-dlp-ejs, and iOS can't spawn Deno or Node. Plan: a custom provider that calls JavaScriptCore through the bridge. Non-YouTube sites work without it.
2. **ffmpeg.** Right now only single-file formats work (no merging, no audio conversion, no embedded thumbnails). Next step is an in-process FFmpeg xcframework.
3. **Background downloads.** The screen is kept awake while downloading because iOS suspends the app otherwise.
4. **Cookies.** Drop a Netscape `cookies.txt` at `Application Support/SealPad/cookies.txt`. A WKWebView login flow can come later.
5. **Updates.** "Check for updates" pulls yt-dlp and its pinned yt-dlp-ejs from PyPI, verifies the SHA-256, and activates it on the next launch. A broken update falls back to the bundled copy.
6. **CI signing.** The IPA is built unsigned (`CODE_SIGNING_ALLOWED=NO`). The "Process Python libraries" step in `project.yml` exports an ad-hoc identity so `install_python` can still sign the Python extension frameworks. Both fixes came from your working repo.
