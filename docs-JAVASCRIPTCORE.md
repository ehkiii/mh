# SealPad JavaScriptCore bridge

This change adds the native callback foundation required for an in-process
JavaScript runtime:

- `JavaScriptRuntime.swift` owns one `JSContext` and evaluates scripts on the
  main thread.
- `PythonBridge` registers the built-in `_sealpad_native` CPython module before
  interpreter startup.
- Python calls `_sealpad_native.evaluate_javascript(source)`; Objective-C
  releases the GIL while synchronously dispatching the evaluation to the main
  queue, then returns the result to Python.
- `bridge.configure()` runs a `1 + 1` startup probe so a missing callback fails
  visibly rather than silently leaving the app without a JS runtime.

## Current scope

This is the transport/runtime foundation, **not yet a complete YouTube
challenge solver**. JavaScriptCore does not provide a browser DOM, browser
network stack, or Node/Deno APIs. yt-dlp's public challenge-provider interface
is available, but its EJS script execution hooks are currently documented as
private/unstable. The next implementation step is a version-aware adapter that
feeds yt-dlp's challenge scripts into this runtime and supplies only the browser
compatibility shims those scripts actually require.

## Test

Run `python3 -m unittest discover -s tests` on the host. The host tests stub the
native module; the actual JavaScriptCore evaluation must be verified in an iOS
build/device run.
