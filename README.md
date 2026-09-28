# SpeakSelection

A macOS menu bar app that reads any selected text aloud with high-quality
on-device voices. Highlight text in any app, right-click → **Services →
Speak Selection**, and it speaks — using the Kokoro-82M neural TTS model
running fully inside the app via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx).
No Python, no sidecar, nothing leaves the Mac.

## What end users experience (one-click install)

1. Download `SpeakSelection.dmg`, drag the app to Applications, open it.
2. A speaker icon appears in the menu bar. On first launch the app
   downloads its voice pack automatically (progress shown in the menu;
   Apple's system voices fill in until it finishes).
3. Select text anywhere → right-click → **Services → Speak Selection**.

No terminal, no setup steps. That's the whole flow.

## Developer setup

Requirements: macOS 13+ (Apple Silicon recommended), Xcode 15+,
`brew install xcodegen`.

```bash
xcodegen                        # generates SpeakSelection.xcodeproj
open SpeakSelection.xcodeproj   # then Cmd-R
```

Xcode resolves the `sherpa-onnx-spm` Swift package automatically on first
open. The app is menu-bar-only (no Dock icon).

**Quick test without the Services menu:** copy some text, click the menu bar
icon, and hit *Speak Clipboard (test)*.

> **API note:** `NativeKokoroEngine.swift` is written against the SherpaOnnx
> Swift wrapper API (`SherpaOnnxOfflineTtsWrapper`,
> `sherpaOnnxOfflineTtsKokoroModelConfig`, …). If the package version you
> resolve exposes slightly different names, that one file is the only place
> to adjust — the rest of the app talks to the `SpeechEngine` protocol.

## Shipping it (signed + notarized DMG)

```bash
./Scripts/release.sh "Developer ID Application: Your Name (TEAMID)"
```

The script builds Release, signs with your Developer ID (hardened runtime),
packages a drag-to-Applications DMG, submits it to Apple for notarization,
and staples the ticket. Prerequisites (Developer Program membership,
certificate, `notarytool store-credentials`) are documented at the top of
the script. Without notarization, users face Gatekeeper's
"unidentified developer" friction — that's the difference between
one-click and not.

**Mac App Store later:** the code avoids everything sandbox-hostile — the
model download is plain URLSession and extraction targets the app's own
container. To go MAS: set `ENABLE_APP_SANDBOX: true` in `project.yml`, add
network-client + user-selected file entitlements, and switch extraction
from `/usr/bin/tar` to an in-process decompressor if review complains.

## First-run model download

- Bundle: `kokoro-en-v0_19` (English, 11 voices) from the sherpa-onnx
  release archives, extracted to
  `~/Library/Application Support/SpeakSelection/`.
- It's a large one-time download; the menu shows live progress and a Retry
  button on failure. Delete the Application Support folder to force a
  re-download.
- Want a smaller download or the newer v1.x voices (e.g. `af_heart`)?
  Swap `bundleName`/`downloadURL` in `ModelDownloader.swift` to
  `kokoro-int8-multi-lang-v1_1` and update the voice table in
  `NativeKokoroEngine.swift` (v1.1 has 103 speakers).

## Enabling the right-click Service

The Services entry registers on first launch (`NSUpdateDynamicServices()`).
Then in any app: select text → right-click → **Services → Speak Selection**.

If it doesn't show up:

1. Force a rescan: `/System/Library/CoreServices/pbs -update` (dev machines
   only — end users just relaunch the app they're speaking from).
2. Quit and relaunch the app you're trying to speak from (apps cache the
   Services menu at launch).
3. Check System Settings → Keyboard → Keyboard Shortcuts… → Services →
   Text — make sure **Speak Selection** is checked.

**Free hotkey:** in that same Services pane, assign a keyboard shortcut to
*Speak Selection* — macOS gives you a global "speak my selection" hotkey
with no extra code and no Accessibility permission.

## Architecture

```
right-click Service (or hotkey)          menu bar UI
        │                                     │
        ▼                                     ▼
ServiceProvider ──────────────► SpeechController (chunking, pipeline, playback)
                                     │                    │
                                     ▼                    ▼
                     NativeKokoroEngine (default)  SystemVoiceEngine (fallback)
                          sherpa-onnx, in-process       AVSpeechSynthesizer
                                     ▲
                                     │ model files
                          ModelDownloader (first launch,
                          progress UI, retry)
```

- Long text is split into sentence-ish chunks; chunk N+1 synthesizes while
  chunk N plays, so speech starts quickly even for long articles.
- "Stop Speaking" is in both the Services menu and the popover; a new
  selection always interrupts the current one.
- The Services pasteboard hands you plain text, so this works in Safari,
  Mail, Preview, Slack, etc. A few Electron apps don't populate the
  Services menu — *Speak Clipboard* is the workaround there.

## Swapping engines later

`SpeechEngine` is a small protocol. To add ElevenLabs/OpenAI/Fish Audio,
implement `synthesize(text:voice:speed:)` returning WAV data and register
it in `SpeechController`. The same protocol is the seam you'd share with an
iOS Share-Sheet-extension version (sherpa-onnx-spm supports iOS 13+ too).
