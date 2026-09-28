# Vendored SherpaOnnx package

Local replacement for the `sherpa-onnx-spm` remote package
(https://github.com/willwade/sherpa-onnx-spm, sherpa-onnx **1.13.2** artifacts).

## Why vendored

The upstream package is unusable from Xcode in every published form
(checked 2026-08-19, latest tag 1.13.16):

- The non-`v` tags ship **two** binary xcframeworks (`sherpa-onnx` +
  `onnxruntime`) whose `Headers/` both contain a `module.modulemap`. Xcode
  copies both header sets into the same `BUILT_PRODUCTS_DIR/include/`, so the
  build dies with *"Multiple commands produce .../include/module.modulemap"*.
- The `v`-prefixed tags (e.g. `v1.13.13`) use a single combined xcframework,
  but their `Package.swift` downloads it from a release URL that 404s.
- The Swift wrapper (`SherpaOnnx.swift`) is entirely `internal` at every tag,
  so an app target could not call it across the module boundary anyway.

## What's here

- `Frameworks/sherpa-onnx.xcframework` — macOS-only (arm64 + x86_64), the two
  upstream static libs merged into one with `libtool`, plus the sherpa-onnx
  C headers/modulemap. One xcframework → one modulemap → no collision.
- `Sources/SherpaOnnx/Reexport.swift` — `@_exported import sherpa_onnx`, so
  `import SherpaOnnx` exposes the C API.
- The Swift convenience wrapper lives in the app target
  (`SpeakSelection/SherpaOnnx.swift`, copied from upstream tag 1.13.16 with
  its import switched to this shim) so its internal API is visible to
  `NativeKokoroEngine.swift`. This mirrors upstream k2-fsa's recommended
  usage of copying `SherpaOnnx.swift` into your project.

## Regenerating the xcframework (e.g. to bump sherpa-onnx)

1. Download `sherpa-onnx.xcframework.zip` and `onnxruntime.xcframework.zip`
   from a sherpa-onnx-spm release (or build from k2-fsa/sherpa-onnx).
2. Merge the macOS slices:
   `libtool -static -o libsherpa-onnx.a <sherpa macos slice>/libsherpa-onnx.a <ort macos slice>/libonnxruntime.a`
   (duplicate-member warnings from onnxruntime.a are harmless)
3. `xcodebuild -create-xcframework -library libsherpa-onnx.a -headers <sherpa macos slice>/Headers -output Frameworks/sherpa-onnx.xcframework`
4. Refresh `SpeakSelection/SherpaOnnx.swift` from the matching upstream tag,
   keeping the `import SherpaOnnx` line in place of `@_exported import sherpa_onnx`.
