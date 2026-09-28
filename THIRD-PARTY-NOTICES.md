# Third-party components

SpeakSelection ships or downloads the components below. This file records
what they are and what they are licensed under. It is a factual inventory,
not legal advice, and it deliberately does not assert a license for
SpeakSelection itself — see **Open question** at the end.

## Linked into the app binary

### sherpa-onnx — Apache License 2.0
<https://github.com/k2-fsa/sherpa-onnx>

Vendored at `Vendor/SherpaOnnx/` as a prebuilt static library
(`libsherpa-onnx.a`, sherpa-onnx 1.13.2, macOS arm64 + x86_64). The Swift
convenience wrapper `SpeakSelection/SherpaOnnx.swift` is copied from upstream
tag 1.13.16. See `Vendor/SherpaOnnx/README.md` for why it is vendored and how
to regenerate it.

### ONNX Runtime — MIT License
<https://github.com/microsoft/onnxruntime>

Merged into the same static library (see the regeneration steps in
`Vendor/SherpaOnnx/README.md`).

### espeak-ng — **GNU General Public License v3.0**
<https://github.com/espeak-ng/espeak-ng>

**This is the component that constrains how SpeakSelection may be licensed
and distributed.**

espeak-ng is statically linked into `libsherpa-onnx.a` — the archive exports
223 `espeak_*` symbols — and Kokoro depends on it for grapheme-to-phoneme
conversion. The Kokoro v1.0 model metadata confirms this with `has_espeak=1`.
It is reached at runtime for any word not found in the bundled lexicons, so
it is not dead code that could simply be stripped.

GPLv3 is a copyleft license. Statically linking GPLv3 code into a program
that is then distributed is generally understood to place the combined work
under GPLv3, which would require offering SpeakSelection's own source to
recipients. Distributing a closed-source, paid binary in this configuration
is the specific risk.

Known options, none yet chosen:

1. **Release SpeakSelection under GPLv3.** Selling GPLv3 software is
   permitted; what is required is that recipients get the source and the
   same rights. Compatible with a paid direct download, incompatible with
   the Mac App Store's terms.
2. **Remove espeak-ng from the G2P path.** Requires a phonemizer whose
   license permits proprietary distribution, plus a sherpa-onnx build with
   espeak-ng compiled out. Largest engineering cost; fully clears the issue.
3. **Rebuild on a TTS stack with no GPL frontend.** Changes the voice
   lineup and quality bar, which is much of the product's appeal.
4. **Obtain a separate license from the espeak-ng copyright holders.**
   espeak-ng has many contributors, so this is usually impractical.

Confirm the chosen path with a lawyer before the first paid release.

## Downloaded at first launch

### Kokoro-82M v1.0 — Apache License 2.0
<https://huggingface.co/hexgrad/Kokoro-82M>

Fetched from the sherpa-onnx `tts-models` release as
`kokoro-int8-multi-lang-v1_0.tar.bz2` and installed to
`~/Library/Application Support/SpeakSelection/`. The archive also contains:

- **espeak-ng-data/** — pronunciation data for espeak-ng, GPLv3 (see above).
- **dict/** — jieba Chinese segmentation dictionaries, MIT License.
- **lexicon-\*.txt** — pronunciation lexicons distributed with the model.
- Its own `LICENSE` file (Apache 2.0), installed alongside the weights.

Because this bundle is downloaded by the user at runtime rather than
redistributed inside the app, it raises a different — not necessarily
smaller — set of questions than the statically linked code above.

## Apple frameworks

AVFoundation, AppKit, SwiftUI, CryptoKit and Carbon (HIToolbox, for the
global hotkey) are used under the Apple SDK license. `AVSpeechSynthesizer`
provides the system-voice fallback and requires no attribution.

## Open question

SpeakSelection has no `LICENSE` file yet. Adding one is deliberately
deferred until the espeak-ng question above is resolved, because that answer
determines which licenses are actually available.
