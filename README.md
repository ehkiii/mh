# SealPad

An iOS media downloader built with SwiftUI, an embedded CPython runtime, and yt-dlp.

## Current integration work

- Native CPython embedding and Swift download UI are already in place.
- The in-app JavaScriptCore callback foundation is being added in `Swift/JavaScriptRuntime.swift` and `ObjC/PythonBridge.m`.
- The JavaScriptCore bridge currently has a host-side contract test; device-level execution still needs an iOS GitHub Actions build and device verification.
- The YouTube challenge-provider adapter and FFmpeg XCFramework are not implemented yet.

See [`docs-JAVASCRIPTCORE.md`](docs-JAVASCRIPTCORE.md) for the bridge design and current limitations.

## Build

The intended build environment is GitHub Actions on macOS. Run `./scripts/bootstrap.sh` and `./scripts/build_ipa.sh` on a compatible macOS/Xcode runner.
