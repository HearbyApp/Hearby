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

### Source code for the prebuilt library

`libsherpa-onnx.a` reports sherpa-onnx 1.13.2 and ONNX Runtime 1.24.4. The
source it was built from, including espeak-ng, is published as release
assets at
<https://github.com/HearbyApp/Hearby/releases/tag/third-party-source-sherpa-onnx-1.13.2>
so it stays available for as long as any Hearby release ships this library.
Each archive is the one pinned by sherpa-onnx 1.13.2's `cmake/` files; where
upstream pins a SHA-256, it matches.

| Archive | SHA-256 |
|---|---|
| `sherpa-onnx-1.13.2.tar.gz` | `9f64f8ee121d751af26fe04863333b22458d2de870e98bb7d3eedf7491ac52e4` |
| `espeak-ng-f6fed6c.zip` (GPLv3) | `70cbf4050e7a014aae19140b05e57249da4720f56128459fbe3a93beaf971ae6` |
| `piper-phonemize-78a788e.zip` | `89641a46489a4898754643ce57bda9c9b54b4ca46485fdc02bf0dc84b866645d` |
| `onnxruntime-1.24.4.tar.gz` | `0cf4d2ee4392fbb8aedaabc6b2ba11b4a680d1071fa4f75546c2289ca5b404cf` |
| `openfst-1.8.5-2026-04-11.tar.gz` | `57fbc4b950ae81b1a0e1e298af15652da968a6723a592b7874e9b4027a80a5b4` |
| `kaldi-decoder-0.3.0.tar.gz` | `b9f34cfb4fd3b1344100eead79ef4d37aa15962274b9e3056de345021f76a1b0` |
| `kaldi-native-fbank-1.22.3.tar.gz` | `9176cc66fc7ce1edf85cf355b06e320c57db6297df74277f575183468893cf61` |
| `simple-sentencepiece-0.7.tar.gz` | `1748a822060a35baa9f6609f84efc8eb54dc0e74b9ece3d82367b7119fdc75af` |
| `cargs-1.0.3.tar.gz` | `ddba25bd35e9c6c75bc706c126001b8ce8e084d40ef37050e6aa6963e836eb8b` |
| `eigen-5.0.1.tar.gz` | `e9c326dc8c05cd1e044c71f30f1b2e34a6161a3b6ecf445d56b53ff1669e3dec` |
| `hclust-cpp-2026-02-25.tar.gz` | `8f14e024c709d73afb40ae69cb22de4b73dba67cbce40f2e518813da8139ab56` |
| `nlohmann-json-3.12.0.tar.gz` | `4b92eb0c06d10683f7447ce9406cb97cd4b453be18d7279320f7b2f025c10187` |
| `sherpa-onnx-spm-1.13.2.tar.gz` (packaging scripts) | `5f929143af222a079e762ba81d483d5dadf6f173eecc991bf976a51fa681400f` |

`Vendor/SherpaOnnx/README.md` describes how the two upstream libraries were
merged into the vendored one. When the library is bumped, publish a new
source release the same way and update this section.

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
