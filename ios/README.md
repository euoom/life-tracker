# iPhone prototype

SwiftUI + AVFoundation + Core Location + App Intents. The Linux workspace cannot
compile or sign iOS apps. Sources are provided, not a tested IPA. Real-device
validation is required before using this to retain important daily records.

## Build on a Mac or remote macOS machine

Requires Xcode with the iOS 17+ SDK and XcodeGen. No packages are required by the
app itself. Change the bundle prefix if it conflicts with an existing app ID.

```sh
brew install xcodegen
cd ios
xcodegen generate
xcodebuild -project LifeTracker.xcodeproj -scheme LifeTracker \
  -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Unsigned builds verify compilation but cannot be installed. Open the generated
project in Xcode, choose your Personal Team for both app and widget, enable
Developer Mode on the iPhone, then sign/install. Free Personal Team profiles last
7 days. A remote unsigned build plus Windows sideloading is a separate path;
we have not verified signing with the Live Activity extension through AltStore.
Do not buy a membership before confirming the intended free signing path.

`../.github/workflows/ios-build.yml` contains a manually triggered macOS compile
check. It is prepared locally only; no remote repository or CI run is created.
It produces no signed installable IPA.

## First device test

1. Enter the PC's reachable LAN/VPN URL (port 18765), matching token, home SSID,
   excluded company SSID list, and a 5- or 10-minute location interval. Save.
   SSIDs are reference settings; the first build does not poll SSIDs itself.
2. Grant microphone, location and Local Network permissions while the app is
   foregrounded. Enable Always location separately if desired and permit Live
   Activities. Permission prompts are not deferred to a locked automation.
3. Start audio and location from the app. Lock the screen for at least 15 minutes.
   Listen to both speakers, check actual mic route and recorded location timestamps.
4. Stop recording. Trigger PC synchronization on Wi-Fi. Confirm API receipts and
   server counts. Disconnect/retry to check that files are not duplicated.
5. Test one-hour rotation. It currently stops and reopens the recorder; a small
   segment-boundary gap is possible. Phone calls stop the recorder and require a
   new explicit start; no call audio or phone numbers are captured.
6. Only then test Shortcuts and locked/cold-start invocation. The initial start
   intents open the app (`openAppWhenRun = true`) deliberately: unattended start
   under lock is an unresolved requirement, not a claimed feature.

No local files are automatically deleted, including acknowledged audio. Settings
survive launch. Audio sessions and active location sessions are not silently
restarted after force quit. Incomplete audio metadata after termination remains
for manual inspection and is not automatically uploaded. Live Activities are
system-limited and may end during very long sessions; long-duration operation
must be tested. Location logs are rate-limited samples of OS updates, not a
5-minute OS timer. Stationary/suspended periods may have gaps. Limiting writes
does not prove low-power GPS operation; measure before optimizing.

## Shortcuts actions

Search the app's actions in Shortcuts (not only its suggested shortcuts).

| Trigger | Actions |
| --- | --- |
| Home Wi-Fi disconnected | Start recording; start location |
| Company Wi-Fi connected | Stop location only |
| Company Wi-Fi disconnected | Start location, unless another excluded Wi-Fi is now connected |
| Home Wi-Fi connected | Stop recording; stop location; PC synchronize |
| Incoming Message automation | Message Record: map Shortcut Input text and sender explicitly |

Message capture does not read the existing Messages database. It records receipt
at the app, not the original SMS timestamp. Unsupported attachments, automation
filters and sender variable behavior must be tested on the actual OS. Existing
message backup import is not implemented in this first slice.

Location and recording have independent start/stop actions. Keep the company
SSID out of recording stop automations. Test whether your OS exposes the desired
Wi-Fi disconnect trigger and immediate-run behavior before relying on it.

## Networking

Uploads use a background URLSession, no cellular access, and file-backed tasks.
Wi-Fi availability does not guarantee that the destination is reachable; the
system schedules transfers and pending failures remain until synchronization is
requested again. Duplicate uploads use stable IDs and server acknowledgments.
The first build permits HTTP for private LAN/VPN testing in Info.plist. Use an
isolated private route or TLS; do not expose the bearer-token API to the internet.
No WireGuard profile is created or switched by this app.

## Windows-only ownership: remote build then local signing

The repository includes `scripts/build-unsigned.sh`, which needs macOS/Xcode.
It generates the project, compiles for a physical iPhone and packages
`ios/build/LifeTracker-unsigned.ipa`. This is an unsigned IPA, not installable
without signing. The script has not yet run on macOS.

1. Put the source in your own GitHub repository (or transfer it to a remote Mac).
   This workspace has not uploaded it or configured a Git remote.
2. In GitHub Actions choose **Build unsigned iOS prototype**, then **Run workflow**.
   On a successful build download the **LifeTracker-unsigned** artifact and unzip
   the outer artifact archive to obtain `LifeTracker-unsigned.ipa`.
3. On Windows follow the AltStore **Classic** / AltServer installation guide:
   https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
   Install the Apple device software versions required by that guide, connect
   your iPhone via USB, trust the PC and install AltStore using your own Apple
   account locally. Do not send account credentials to the agent.
4. Open the IPA with AltStore (My Apps, plus/import). The tool signs and installs
   it using your account. Enable Developer Mode and developer trust when iOS
   asks. Actual free signing with this app's widget/Live Activity extension has
   not been verified; retain the extension because the recording state uses it.
5. Refresh the app before its 7-day profile expires. This refresh is independent
   of rebuilding the source. Compile a new IPA when the app code changes.

If CI compilation or signing fails, inspect that step's log before changing
capabilities. Do not treat a downloaded unsigned IPA as a tested runnable app.
