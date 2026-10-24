# Release readiness — first TestFlight build

Everything checked before the first Third Hand beta, what passed, and what is still
blocked. Issue references are to the repository tracker (#33–#38).

**Verdict: build-ready, not upload-ready.** The archive, the export, the icon, the
manifest, the metadata and the versioning all verify on this machine. One manual
portal step — creating the App Store Connect app record — blocks the upload, and
nothing in `asc` v0.18.2 can do it.

| Area | Result | Where |
| --- | --- | --- |
| Simulator build (iPhone 17 Pro) | **pass** | §1 |
| Test suite | **pass** (27 tests, 6 suites) | §1 |
| App icon, flat and alpha-free | **pass** | §2 |
| Launch screen | **pass** | §2 |
| Archive + export to `.ipa` | **pass** (1.8 MB) | §3 |
| Privacy manifest | **pass** (in the bundle) | §4 |
| Version pair single-sourced | **pass** | §5 |
| Metadata, privacy policy, screenshots | **pass** | §6, §7 |
| Secrets not committed | **pass** | §8 |
| App Store Connect app record | **blocked: portal** | §9 |
| TestFlight internal group | **blocked: portal** (follows §9) | §9 |
| iPad screenshots | **not applicable** (iPhone-only) | §7 |

---

## 1. Build and tests

Both run from a clean checkout at `HEAD` plus the release changes in this branch,
so nothing here depends on uncommitted local state.

```console
$ xcodegen generate
$ xcodebuild -scheme ThirdHand -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath /tmp/pulse-rr CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **

$ xcodebuild test -scheme ThirdHand -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath /tmp/pulse-rr CODE_SIGNING_ALLOWED=NO
✔ Test run with 27 tests in 6 suites passed after 0.189 seconds.
** TEST SUCCEEDED **
```

Toolchain: Xcode 27.0 (27A266a), iOS 27.0 simulator runtime, macOS on Apple
silicon. Deployment target 18.0.

Three warnings survive in the Release-adjacent build, all pre-existing and none
release-blocking:

| Location | Warning |
| --- | --- |
| `ThirdHandCore/.../CommandReader.swift:86` | immutable value `index` never used |
| `ThirdHand/Sync/SyncCoordinator.swift:289` | main-actor property `name` read from a nonisolated context |
| AppIntents metadata processor | skipped, no `AppIntents.framework` dependency |

The AppIntents line is informational: the widget has no AppIntent yet, so the
processor has nothing to do.

---

## 2. Icon and launch screen (#33)

### The icon is flat, opaque, and reproducible

```console
$ for f in ThirdHand/Assets.xcassets/AppIcon.appiconset/*.png; do
>   echo -n "$(basename $f): "; sips -g hasAlpha -g pixelWidth -g pixelHeight "$f" | tail -3 | tr '\n' ' '; echo
> done
AppIcon-1024-dark.png:   hasAlpha: no   pixelWidth: 1024   pixelHeight: 1024
AppIcon-1024-tinted.png: hasAlpha: no   pixelWidth: 1024   pixelHeight: 1024
AppIcon-1024.png:        hasAlpha: no   pixelWidth: 1024   pixelHeight: 1024
```

`hasAlpha: no` on all three — that is the check App Store Connect rejects on, and
the failure mode is opaque: the upload errors with "Invalid Image" and no reason.
The 120pt derivative inside the exported bundle is also alpha-free:

```console
$ sips -g hasAlpha /tmp/ipa-y/Payload/ThirdHand.app/AppIcon60x60@2x.png
  hasAlpha: no
```

The pixels come from `Scripts/make-icon.swift`, committed, not from an art tool:

```sh
swift Scripts/make-icon.swift ThirdHand/Assets.xcassets/AppIcon.appiconset
```

It draws through Core Graphics into a `CGContext` created with
`CGImageAlphaInfo.noneSkipLast` (the "none" is the whole point — `premultipliedLast`
would reintroduce alpha), in sRGB, at exactly 1024×1024. No rounded corners: iOS
applies the mask, and baking a mask into the artwork produces the
double-rounded-corner look reviewers flag. The mark is a board pulse that bleeds
off both edges plus a single filled attention dot, and it was checked down to a
40pt render, not only at 1024. `ThirdHand/Assets.xcassets/AppIcon.appiconset/Contents.json`
declares the universal 1024 slot plus the two `appearances` variants:

- **Any** — `#D70015` field with a white mark
- **Dark** — `#000000` field with the `#FF453A` mark
- **Tinted** — black field, monochrome mark

### Launch screen

`UILaunchScreen` is declared with `UIColorName: LaunchBackground` in
`project.yml`, backed by `ThirdHand/Assets.xcassets/LaunchBackground.colorset`
(`#F2F2F7` light, `#000000` dark). The colours match `DESIGN.md` §2 tokens, so the
launch does not flash a mismatched white. Confirmed in the exported plist:

```console
$ plutil -p /tmp/ipa-y/Payload/ThirdHand.app/Info.plist | grep -A2 UILaunchScreen
"UILaunchScreen" => {
  "UIColorName" => "LaunchBackground"
}
```

No launch storyboard. There is nothing to see without the brand mark, and the
background token is the brand.

---

## 3. Archive and export (#36)

The proof is a real `.ipa`, not a dry run. Run in a clean worktree
(`/tmp/pulse-verify`) so another branch's in-flight edits could not mask a signing
failure:

```console
$ fastlane ios build_only
==> archive 0.1.0 (1)
** ARCHIVE SUCCEEDED **
==> export .ipa
Exported Third Hand to: /tmp/pulse-verify/build/export
** EXPORT SUCCEEDED **
ipa: /tmp/pulse-verify/build/export/ThirdHand.ipa (1.8 MB, version 0.1.0 build 1)
```

```console
$ ls -lh build/export/ThirdHand.ipa
-rw-r--r--@ 1 white-box  wheel   1.8M Oct 23 17:17 build/export/ThirdHand.ipa
$ shasum -a 256 build/export/ThirdHand.ipa
50d92a24b23f1be4b07f0bcfc3301e5b6cbd91b8c76e42a2f9159e2fdf5eda74
```

1.8 MB — plausible for a binary with no bundled media, and small enough that the
size itself is evidence nothing unexpected was packaged.

### Entitlements in the signed binary

Automatic signing produced the App Store profile and the iCloud entitlements
without a manual provisioning step:

```console
$ codesign -d --entitlements :- Payload/ThirdHand.app
application-identifier              4QJ25Y85MX.com.steveafrost.thirdhand
beta-reports-active                 true          <- required for TestFlight
com.apple.developer.icloud-container-identifiers   iCloud.com.steveafrost.thirdhand
com.apple.developer.icloud-services               CloudDocuments
com.apple.security.application-groups             group.com.steveafrost.thirdhand
get-task-allow                      false         <- correctly a release build
```

`beta-reports-active` is the entitlement TestFlight uses to accept a build, and it
is present. Both identifiers already existed on the portal, which is why no manual
capability work was needed.

`.dSYM` files are produced for both targets, which is what symbolicates crash
reports later:

```console
$ ls build/ThirdHand.xcarchive/dSYMs/
ThirdHand.app.dSYM  ThirdHandWidgets.appex.dSYM
```

### Not uploaded

Nothing was sent to App Store Connect — there is no app record to send it to, and
uploading to prove the path works would leave a rejected build in the account.
`Scripts/upload-testflight.sh` gates on both credentials and app id and was
verified in both failure modes:

```console
$ ./Scripts/upload-testflight.sh --dry-run
asc builds upload --app-id <APP_ID> --file build/export/ThirdHand.ipa \
    --version 0.1.0 --build-number 1 --platform ios --wait
(dry run: nothing uploaded)  # exit 0

$ ./Scripts/upload-testflight.sh build/export/ThirdHand.ipa   # with no creds
No App Store Connect credentials found. ...
exit 3
```

The `fastlane beta` lane calls `require_asc_auth!` *before* `build_only`, so a
missing secret costs seconds instead of a six-minute archive. Verified:

```console
$ THIRDHAND_ASC_APP_ID= fastlane ios beta
[!] THIRDHAND_ASC_APP_ID is empty - there is no App Store Connect app record for
com.steveafrost.thirdhand, so there is nothing to upload to.
...
Nothing was built or uploaded.
```

That is a failure, but the right one: it happened in under a second and built
nothing.

---

## 4. Privacy manifest (#38)

### What the scan found

Two required-reason API categories are used. The scan:

```console
$ grep -rn "UserDefaults" --include=*.swift Third Hand ThirdHandCore/Sources ThirdHandWidgets | grep -v Tests | wc -l
9
$ grep -rn "attributesOfItem\|modificationDate" --include=*.swift Third Hand ThirdHandCore/Sources ThirdHandWidgets
ThirdHandCore/.../FileCloudContainer.swift:101,105,107,108
ThirdHandCore/.../CloudContainer.swift:39,66
ThirdHandCore/.../ICloudContainer.swift:78,87,95
$ grep -rn "systemUptime\|mach_absolute_time\|statfs\|volumeAvailableCapacity" --include=*.swift Third Hand ThirdHandCore/Sources ThirdHandWidgets
(no matches)
```

- **`UserDefaults` (CA92.1)** — nine reads/writes: the preamble-shown flag and the
  app-group suite the widget reads (filter, collapsed sections, last-viewed).
  Nothing leaves the app.
- **File timestamp (C617.1)** — three `attributesOfItem(...)[.modificationDate]`
  reads, all on the app's own files inside its own iCloud container, used to
  decide whether the Mac mirror is newer than the device.
- **Not used:** disk space (`statfs`/`volumeAvailableCapacity`), system boot time
  (`systemUptime`/`mach_absolute_time`), active keyboard. So no other category is
  declared — over-declaring is itself a review risk.

### The manifest

`ThirdHand/PrivacyInfo.xcprivacy` (XcodeGen includes it automatically; no `project.yml`
entry is needed, confirmed by 4 references in the generated `project.pbxproj`):

```xml
NSPrivacyTracking            false
NSPrivacyTrackingDomains     []          (empty)
NSPrivacyCollectedDataTypes  []          (empty — Data Not Collected)
NSPrivacyAccessedAPITypes    UserDefaults   [CA92.1]
                             FileTimestamp  [C617.1]
```

Verified inside the shipped bundle, not only in the source tree:

```console
$ unzip -l build/export/ThirdHand.ipa | grep -i privacy
     1883  10-23-2026 17:17   Payload/ThirdHand.app/PrivacyInfo.xcprivacy
```

`plutil -lint` passes, and the plist parses back to exactly the four keys above.

### Data Not Collected — the reasoning

The App Privacy questionnaire answer is **No, we do not collect data from this
app**, and it is defensible rather than merely convenient:

- Calendar and reminders are read and stored **on the device only**.
- The iCloud copy goes to the **user's own private container** under their Apple
  ID. The developer has no server, no key and no visibility. Apple's definition of
  "collected" excludes data the developer cannot access.
- No account, no identifier, no analytics, no third-party SDK. Confirmed against
  `Package.swift`: the only dependency is the local `ThirdHandCore` target, and the
  SDK grep for Firebase/Amplitude/Mixpanel/Segment/Sentry/Crashlytics returns
  nothing.

The app also makes no network requests of its own — the only `URLSession`-adjacent
code is none at all; the `http://` grep hits are comments explaining that such
links are deliberately dropped.

---

## 5. Versioning (#35)

One definition each, in `project.yml`, substituted into both targets:

```console
$ grep -n 'MARKETING_VERSION\|CURRENT_PROJECT_VERSION' project.yml
MARKETING_VERSION: "0.1.0"
CURRENT_PROJECT_VERSION: "1"
```

The exported binary agrees (`0.1.0` / `1`), and the widget cannot drift because it
references the same values. `marketing_version` is `0.1.0` because this is a first
beta, not a 1.0 — the store listing shows it, so it should not claim more than the
build delivers.

`Scripts/bump-build.sh` is exercised for the cases that actually occur:

| Case | Input | Output | Result |
| --- | --- | --- | --- |
| increment | — | `2` | pass |
| increment again | — | `3` | pass |
| explicit same value | `3` | `3` | pass (no-op, stays idempotent) |
| count down | `2` at `3` | — | exit 1, refuses |
| non-numeric arg | `/tmp/nonexist` | — | exit 1, "'/tmp/nonexist' is not a number" |
| from another cwd | — | `4` | pass (resolves its own root) |

Left at build **`1`** for the first upload. `set -eu`, an atomic temp-file rewrite,
stdout-only output (so `BUILD=$(...)` works), and a guard that exits if the key
ever appears twice.

`fastlane/ExportOptions.plist` is set with `method: app-store-connect` and
`manageAppVersionAndBuildNumber: false` — the latter matters, or Apple renumbers
the build and `project.yml` stops being the source of truth.

---

## 6. Metadata (#34)

`docs/APPSTORE-METADATA.md` carries every field with its length measured against
its limit:

| Field | Value | Length / limit |
| --- | --- | --- |
| Name | `Third Hand — What Needs You` | 22 / 30 |
| Subtitle | `Your day, ordered by urgency` | 28 / 30 |
| Promotional text | see the doc | 155 / 170 |
| Description | see the doc | 2 542 / 4 000 |
| Keywords | 11 comma-separated terms | 86 / 100 |

No keyword repeats a word from the name — that wastes characters, because the name
and subtitle are separately indexed. Plain `Third Hand` is taken, which is why the name
is qualified; the Home Screen label stays `Third Hand` via `CFBundleDisplayName`, and
those are independent fields.

Category **Productivity**, no secondary. Age rating **4+** with every content
question answered None/No: no user-generated content, messaging, ads, gambling or
web browsing, and the app only shows the user's own data.

---

## 7. Privacy policy and screenshots (#34)

### Policy

`docs/PRIVACY.md` is a real policy, not a stub: what is read, where it goes, what
is explicitly not done, how to delete everything, the children's section, and a
dated change clause. `docs/SUPPORT.md` pairs with it. Both render on GitHub, which
gives a hostable URL with no new infrastructure:

- `https://github.com/steveafrost/thirdhand-ios/blob/main/docs/PRIVACY.md`
- `https://github.com/steveafrost/thirdhand-ios/blob/main/docs/SUPPORT.md`

If a reviewer refuses a `blob/` URL, GitHub Pages on `/docs` serves the same files
at `…github.io/thirdhand-ios/PRIVACY.html` — recorded in `APPSTORE-METADATA.md` §7, with
the switch documented. The URL actually entered in App Store Connect has to be
recorded there before submission; it is deliberately left blank rather than
guessed.

### Screenshots

Eight real simulator captures in `docs/screenshots/`, from the debug fixture board
with the status bar pinned to 9:41 (`DESIGN.md` §12). No mockups, no lorem.

| File | Pixels | Device | Screen |
| --- | --- | --- | --- |
| `01-board-now-69.png` | 1320×2868 | 17 Pro Max | Board, Now expanded |
| `02-detail-quick-actions-69.png` | 1320×2868 | 17 Pro Max | Item detail |
| `03-snooze-69.png` | 1320×2868 | 17 Pro Max | Snooze sheet |
| `04-closed-review-69.png` | 1320×2868 | 17 Pro Max | Recently Closed |
| `05-all-clear-69.png` | 1320×2868 | 17 Pro Max | Empty state |
| `06-permission-preamble-69.png` | 1320×2868 | 17 Pro Max | Permission preamble |
| `07-board-dark-69.png` | 1320×2868 | 17 Pro Max | Dark appearance |
| `08-board-61.png` | 1179×2556 | iPhone 16 | 6.1" board |

Size correctness was checked, not assumed. `asc` v0.18.2 rejects `APP_IPHONE_69`
and `APP_IPHONE_66` outright ("Unknown display type"), so 6.9" pixels go into the
`APP_IPHONE_67` bucket — which is why 1320×2868 is the target. The 6.1" capture is
1179×2556, the exact `APP_IPHONE_61` size.

Three shots from `DESIGN.md` §12 are not captured:

- **Widgets and Live Activity** — those targets are still in progress in
  `ThirdHandWidgets/`, so a capture would show a placeholder.
- **iPad** — not applicable; `UIDeviceFamily` is `[1]`.
- **Completion animation and Reduce Transparency** — need a mid-animation frame and
  an accessibility toggle that is not scripted yet.

Missing screenshots block *submission*, not the first TestFlight build. They are
listed in `APPSTORE-METADATA.md` §8 so they are not forgotten.

**Thresholds and defaults used for these captures** — recorded because they are
invisible in the image:

| Setting | Value | Why |
| --- | --- | --- |
| Dynamic Type | default (large) | AX sizes push a single row past the screen; a hero shot should look normal |
| Appearance | light, except `07` | light is the shipping default |
| Status bar | 9:41, full battery, 3 Wi-Fi bars, 4 cellular | `DESIGN.md` §12; avoids an RF-shaped status bar |
| Data | `-ThirdHandDemoBoard` fixtures | compiled out of Release via `#if DEBUG` |

---

## 8. Secrets and repository hygiene

```console
$ git ls-files | grep -E '\.p8$|\.p12$|\.env$|\.ipa$|\.mobileprovision$'
(none)
```

The only key-shaped strings in the tree are placeholder paths in error messages
and `.env.example` (`/path/to/AuthKey_38R6G5B784.p8`) — a path, not a key. `.gitignore`
covers `.p8`, `.p12`, `.mobileprovision`, `fastlane/.env`, `build/`, `*.ipa`,
`*.dSYM.zip`, and now also `fastlane/README.md`, which fastlane regenerates on every
run with boilerplate that would only go stale.

`.env.example` is committed with every key and no value. The real file is
gitignored.

---

## 9. Blocked on the developer portal

These need a human with a browser; nothing here can be scripted with the current
tooling. Both are one-time.

### 9.1 App Store Connect app record — **blocked: portal**

There is no app record for `com.steveafrost.thirdhand`, and `asc` cannot create one.
Confirmed rather than assumed:

```console
$ asc apps list | jq '.data | length'
10
$ asc apps list | jq -r '.data[].bundleId' | grep -c pulse
0
$ asc apps create 2>&1 | head -1
Error: Unexpected argument 'create'
$ asc privacy 2>&1 | head -1
Error: Unexpected argument 'privacy'
```

Ten apps in the account, none is Third Hand. The App Store Connect web API has no
public create-app endpoint, so this is a click-path:

**App Store Connect → My Apps → + → New App**

| Field | Value |
| --- | --- |
| Platform | iOS |
| Name | `Third Hand — What Needs You` |
| Primary Language | English (U.S.) |
| Bundle ID | `Third Hand` (`com.steveafrost.thirdhand`) |
| SKU | `thirdhand-ios-001` |
| User Access | Full Access |

Then record the numeric id: `echo "THIRDHAND_ASC_APP_ID=<ID>" >> fastlane/.env`.

### 9.2 TestFlight internal group — **blocked: portal** (follows 9.1)

`asc testflight groups create --app-id …` fails without a record, because the
group hangs off the app. `fastlane ios groups` is written and idempotent; it just
needs the id. Full runbook: [`TESTFLIGHT.md`](TESTFLIGHT.md).

### 9.3 Capabilities — already satisfied

App Groups (`group.com.steveafrost.thirdhand`), the iCloud container
(`iCloud.com.steveafrost.thirdhand`, Documents only) and the matching profiles were
already on the portal, which is why the archive picked them up automatically. No
action needed. Verified in the signed entitlements in §3.

---

## 10. Checks that were not run, and why

Honest accounting of the gaps in this checklist:

| Check | Status | Reason |
| --- | --- | --- |
| On-device (not simulator) build | not run | no device attached; the Release archive targets `generic/platform=iOS`, which is a device build |
| Upload to App Store Connect | not run | blocked on §9.1; uploading a build that will be rejected would leave cruft |
| App Store validation / review | not run | needs the record first |
| TestFlight install on a real device | not run | needs an uploaded build and an invited tester |
| App Privacy published | not run | portal-only; `asc` has no privacy subcommand |
| Widget / Live Activity screenshots | not captured | target still in progress |
| iPad screenshots | not applicable | `UIDeviceFamily = [1]` |
| StoreKit / IAP review | not applicable | no purchases, no subscriptions |

## What "done" means here

For #33, #35, #36 and #38 the deliverables verify on this machine and can be
closed. For #34, the metadata, policy and screenshots exist and are correct, but
the policy URL is not entered anywhere yet and three screenshot families are
outstanding — that issue should stay open with a `blocked: portal` marker until
the app record exists. #37 is entirely blocked on 9.1; the code is written, the
portal step is not possible from here.
