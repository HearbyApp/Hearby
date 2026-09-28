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

`SpeakSelection.xcodeproj` is generated and git-ignored — edit `project.yml`
and re-run `xcodegen`, never the project file. The same goes for
`SpeakSelection/Info.plist`: xcodegen rewrites it from the `info.properties`
block in `project.yml` on every run.

sherpa-onnx is vendored at `Vendor/SherpaOnnx/` (see its README for why).
The app is menu-bar-only (no Dock icon).

**Quick test without the Services menu:** copy some text, click the menu bar
icon, and hit *Speak Clipboard (test)*.

**Tests:**

```bash
xcodebuild test -project SpeakSelection.xcodeproj -scheme SpeakSelection \
  -destination 'platform=macOS,arch=arm64'
```

They cover text chunking edge cases and the integrity of the 54-entry
speaker table — hand-transcribed data where a typo produces the wrong
voice rather than an error. `release.sh` runs them before building.

**Headless check** that the installed voice bundle really synthesizes:

```bash
SpeakSelection.app/Contents/MacOS/SpeakSelection --self-test
```

It verifies every file the engine config references, loads the model,
checks the default voice against the speaker table, and synthesizes a
phrase — exiting non-zero on any failure. `release.sh` runs it before
signing.

**App icon:** drawn in code, not stored as a design asset. Regenerate with
`./Scripts/make-icon.swift` after editing it.

> **API note:** `NativeKokoroEngine.swift` is written against the SherpaOnnx
> Swift wrapper API (`SherpaOnnxOfflineTtsWrapper`,
> `sherpaOnnxOfflineTtsKokoroModelConfig`, …). If the package version you
> resolve exposes slightly different names, that one file is the only place
> to adjust — the rest of the app talks to the `SpeechEngine` protocol.

## Repository notes

`Vendor/SherpaOnnx/Frameworks/sherpa-onnx.xcframework/.../libsherpa-onnx.a`
is a 167 MB binary committed directly. That is fine locally but exceeds
GitHub's 100 MB per-file limit, so **install Git LFS and migrate it before
adding a remote**:

```bash
brew install git-lfs && git lfs install
git lfs track "*.a"
git add .gitattributes
git lfs migrate import --include="*.a" --everything
```

## Licensing — unresolved

espeak-ng (**GPLv3**) is statically linked into the vendored sherpa-onnx
library and is reached at runtime for out-of-vocabulary words. This
constrains how the app may be licensed and sold, and is why there is no
`LICENSE` file yet. See `THIRD-PARTY-NOTICES.md` for the full picture and
the options. Resolve it before the first paid release.

## Shipping it (signed + notarized DMG)

```bash
./Scripts/release.sh "Developer ID Application: Your Name (TEAMID)"
```

The script runs the tests, builds a universal Release, runs the self-test,
signs inside-out with your Developer ID (hardened runtime), packages a
drag-to-Applications DMG, notarizes and staples it, verifies the result with
`spctl`, and generates the Sparkle appcast. Prerequisites (Developer Program
membership, certificate, `notarytool store-credentials`) are documented at
the top of the script. Without notarization, users face Gatekeeper's
"unidentified developer" friction — that's the difference between
one-click and not.

**Signing is inside-out, never `--deep`.** Sparkle ships four nested bundles
(`Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`) plus the
framework itself. Each is signed before the bundle enclosing it, or the
outer signature is invalidated as soon as anything inside changes.

## Auto-update (Sparkle)

**Before the first release**, replace `YOUR-GITHUB-USERNAME` in
`project.yml`'s `SUFeedURL`. The app disables auto-update while the
placeholder is present, and `release.sh` refuses to build.

The EdDSA key pair is already generated. The **private key is in the release
machine's login Keychain** (item: "Private key for signing Sparkle updates")
and is not in this repository. Back it up somewhere safe — losing it means
no shipped copy of the app can ever be updated again, and regenerating it
strands every existing install. The public half is `SUPublicEDKey` in
`project.yml`.

`release.sh` needs Sparkle's command-line tools at `~/.sparkle/bin` (or set
`SPARKLE_BIN`). Get them from the `Sparkle-*.tar.xz` asset on
[Sparkle's releases page](https://github.com/sparkle-project/Sparkle/releases).

Each GitHub release must attach **both** the DMG and `appcast.xml`. The feed
URL points at `/releases/latest/download/appcast.xml`, so publishing a
release without the appcast breaks updates for everyone.

**Mac App Store later:** the code avoids everything sandbox-hostile — the
model download is plain URLSession and extraction targets the app's own
container. To go MAS: set `ENABLE_APP_SANDBOX: true` in `project.yml`, add
network-client + user-selected file entitlements, and switch extraction
from `/usr/bin/tar` to an in-process decompressor if review complains.

## First-run model download

- Bundle: `kokoro-int8-multi-lang-v1_0` — 132 MB, 54 voices, of which 28 are
  English (20 US including `af_heart`, the default; 8 UK). The rest cover
  Spanish, French, Italian, Portuguese, Hindi, Japanese and Chinese.
  Extracted to `~/Library/Application Support/SpeakSelection/`.
- The download is SHA-256 verified before extraction; a corrupt archive is
  deleted rather than unpacked. The menu shows live progress, a verifying
  step, and a Retry button on failure.
- Bundles from earlier app versions are deleted once the current one
  installs. Delete the Application Support folder to force a re-download.

**Choosing a different bundle.** `ModelDownloader.bundleName` +
`downloadURL` + `expectedSHA256` select it, and
`NativeKokoroEngine.voiceTable` must be regenerated to match — a wrong
speaker id does not error, it just speaks as the wrong person. The model
carries its own authoritative mapping:

```bash
strings model.int8.onnx | grep -o 'id2speaker.*' | head -1
```

Two bundles worth knowing about: `kokoro-int8-en-v0_19` (103 MB) is the
int8 build of the original English-only model, 11 voices.
`kokoro-int8-multi-lang-v1_1` is newer but is the **-zh** release — 103
voices of which only three are English, so it is a regression here despite
the higher version number.

## First run

A menu-bar-only app that opens no window looks like a failed launch, so the
first launch of each version shows a welcome window: where the app lives,
the ⌃⌥S / ⌃⌥X shortcuts, the Accessibility grant, and an "Open at login"
toggle. Reopen it any time from *Help* in the menu bar popover.

**Accessibility is only needed for the keyboard shortcut** — it reads the
selection out of the frontmost app. The right-click Services entry works
without it, because macOS hands the text over directly. The popover shows a
warning only while the shortcut is actually inactive, and clears it within a
second of the grant being made in System Settings.

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
