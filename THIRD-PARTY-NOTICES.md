# Third-party components

Hearby ships or downloads the components below. This file records
what they are and what they are licensed under. It is a factual inventory,
not legal advice. Hearby itself is licensed under the GNU General
Public License, version 3 or later (see `LICENSE`).

## Linked into the app binary

### sherpa-onnx — Apache License 2.0
<https://github.com/k2-fsa/sherpa-onnx>

Vendored at `Vendor/SherpaOnnx/` as a prebuilt static library
(`libsherpa-onnx.a`, sherpa-onnx 1.13.2, macOS arm64 + x86_64). The Swift
convenience wrapper `Hearby/SherpaOnnx.swift` is copied from upstream
tag 1.13.16. See `Vendor/SherpaOnnx/README.md` for why it is vendored and how
to regenerate it.

### ONNX Runtime — MIT License
<https://github.com/microsoft/onnxruntime>

Merged into the same static library (see the regeneration steps in
`Vendor/SherpaOnnx/README.md`).

### espeak-ng — **GNU General Public License v3.0**
<https://github.com/espeak-ng/espeak-ng>

**This is the component that determines Hearby's own license.**

espeak-ng is statically linked into `libsherpa-onnx.a` — the archive exports
223 `espeak_*` symbols — and Kokoro depends on it for grapheme-to-phoneme
conversion. The Kokoro v1.0 model metadata confirms this with `has_espeak=1`.
It is reached at runtime for any word not found in the bundled lexicons, so
it is not dead code that could simply be stripped.

GPLv3 is a copyleft license: a program that links GPLv3 code and is then
distributed must itself be offered under GPLv3, source included. That is why
Hearby is GPLv3-or-later. Apache 2.0 and MIT, the licenses of every
other linked component, are compatible with it.

A later closed-source version would need espeak-ng removed from the
grapheme-to-phoneme path first: a phonemizer whose license permits
proprietary distribution, plus a sherpa-onnx build with espeak-ng compiled
out.

### Sparkle — MIT License
<https://github.com/sparkle-project/Sparkle>

Auto-update framework, embedded in the app bundle.

## Downloaded at first launch

### Kokoro-82M v1.0 — Apache License 2.0
<https://huggingface.co/hexgrad/Kokoro-82M>

Fetched from the sherpa-onnx `tts-models` release as
`kokoro-multi-lang-v1_0.tar.bz2` and installed to
`~/Library/Application Support/Hearby/`. The archive also contains:

- **espeak-ng-data/** — pronunciation data for espeak-ng, GPLv3 (see above).
- **dict/** — jieba Chinese segmentation dictionaries, MIT License.
- **lexicon-\*.txt** — pronunciation lexicons distributed with the model.
- Its own `LICENSE` file (Apache 2.0), installed alongside the weights.

The bundle is downloaded by the app from the sherpa-onnx release page
rather than redistributed inside it.

## Apple frameworks

AVFoundation, AppKit, SwiftUI, CryptoKit and Carbon (HIToolbox, for the
global hotkey) are used under the Apple SDK license. `AVSpeechSynthesizer`
provides the system-voice fallback and requires no attribution.
