# Release process — Pulse iOS

How a change on `main` becomes a TestFlight build. Covers versioning, archiving,
uploading, and where things land.

```
main ──► fastlane beta ──► xcodegen ──► xcodebuild archive ──► export .ipa ──► asc builds upload ──► TestFlight
              │                                                                                        │
              └── Scripts/bump-build.sh writes project.yml                                     Pulse Beta
```

---

## 1. The version pair has one home

| Value | Lives in | Written by |
| --- | --- | --- |
| `MARKETING_VERSION` (`0.1.0`) | `project.yml`, once | a human, in a PR |
| `CURRENT_PROJECT_VERSION` (`1`, `2`, …) | `project.yml`, once | `Scripts/bump-build.sh` only |

`project.yml` is the only source. `Info.plist` never hardcodes either value — it
reads `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`, and XcodeGen
substitutes them at generate time. Both targets (app and widget) declare the same
two references, so the widget can never drift from the app; TestFlight rejects a
build whose extension version differs from its host.

Verify with:

```sh
grep -n 'MARKETING_VERSION\|CURRENT_PROJECT_VERSION' project.yml   # exactly one definition each
xcodegen generate && xcodebuild -showBuildSettings -scheme ThirdHand -configuration Release \
  | grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION'
```

### Bump policy

- **`MARKETING_VERSION`** — `MAJOR.MINOR.PATCH`. Minor for features, patch for
  fixes, major only for a redesign. It appears on the store listing.
- **`CURRENT_PROJECT_VERSION`** — increments on **every** upload, never repeats,
  never goes backwards. TestFlight refuses a build number it has already seen, so
  this is not a style preference.
- The build number is not the same thing as a commit count. Do not derive it from
  git; a rebase or squash would renumber history and re-use a build number.

### Bumping

```sh
./Scripts/bump-build.sh          # 1 -> 2, prints "2"
./Scripts/bump-build.sh 41       # force to 41 (e.g. to match App Store Connect)
```

It is idempotent and CI-safe:

- `set -eu`, so a failure stops the lane rather than shipping a stale number
- rewrites `project.yml` through a temp file, so an interrupted run cannot leave
  a half-written YAML
- refuses to count down (`bump-build.sh 10` when the current value is 12 exits 1)
- exactly-one-definition guard: if `CURRENT_PROJECT_VERSION` ever appears twice,
  it exits 1 rather than guessing which one to edit
- prints **only** the number on stdout, so `BUILD=$(./Scripts/bump-build.sh)` works

Ask App Store Connect what it already holds before a manual bump:

```sh
asc builds next-number --app-id <APP_ID> --version 0.1.0 --platform ios
```

---

## 2. Release build settings

Set in `project.yml` under `settings.configs.Release`, so they apply to the app
and the widget without duplicating per target:

| Setting | Value | Why |
| --- | --- | --- |
| `SWIFT_COMPILATION_MODE` | `wholemodule` | Whole-module optimization; smaller and faster than incremental |
| `SWIFT_OPTIMIZATION_LEVEL` | `-O` | Optimized, no asserts stripped unexpectedly beyond `-O` semantics |
| `DEBUG_INFORMATION_FORMAT` | `dwarf-with-dsym` | Produces the `.dSYM` that symbolicates TestFlight crash reports |
| `ENABLE_NS_ASSERTIONS` | `NO` | Assertions out of shipped builds |
| `VALIDATE_PRODUCT` | `YES` | Runs Apple's validation during the archive |
| `ENABLE_TESTABILITY` | `NO` | `@testable import ThirdHandCore` cannot leak into a Release build |

`SWIFT_STRICT_CONCURRENCY = complete` and `ENABLE_USER_SCRIPT_SANDBOXING = YES`
stay on in both configurations.

---

## 3. Archiving and exporting

### By hand

```sh
xcodegen generate
./Scripts/bump-build.sh
xcodebuild archive \
  -project ThirdHand.xcodeproj -scheme ThirdHand -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/ThirdHand.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=4QJ25Y85MX CODE_SIGN_STYLE=Automatic
xcodebuild -exportArchive \
  -archivePath build/ThirdHand.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist fastlane/ExportOptions.plist \
  -allowProvisioningUpdates
```

The `.ipa` lands at `build/export/ThirdHand.ipa`. The `.dSYM` files are inside
`build/ThirdHand.xcarchive/dSYMs/` (`ThirdHand.app.dSYM` and
`ThirdHandWidgets.appex.dSYM`).

`-allowProvisioningUpdates` is what lets automatic signing create the App Store
provisioning profiles on the first archive. Without it, a fresh machine fails at
export with "no profiles for com.steveafrost.thirdhand were found".

### With fastlane

```sh
fastlane ios build_only   # archive + export, no bump, no upload — use this to check signing
fastlane ios beta         # bump + archive + export + upload
```

### `fastlane/ExportOptions.plist`

| Key | Value | Note |
| --- | --- | --- |
| `method` | `app-store-connect` | The current name for App Store distribution |
| `destination` | `export` | Write the `.ipa` next to the archive, do not auto-upload |
| `signingStyle` | `automatic` | Matches `CODE_SIGN_STYLE` in `project.yml` |
| `teamID` | `4QJ25Y85MX` | The seed id |
| `uploadSymbols` | `true` | dSYMs go to Apple, so TestFlight crashes symbolicate |
| `manageAppVersionAndBuildNumber` | `false` | **Critical:** otherwise Apple renumbers the build and `project.yml` stops being the source of truth |
| `provisioningProfiles` | empty | Automatic signing fills them in |

---

## 4. Uploading

The upload path is the `asc` CLI, not `altool`/`notarytool`. `asc` is already
authenticated with an App Store Connect API key, so no app-specific password is
needed anywhere in this repo.

```sh
asc builds upload \
  --app-id <APP_ID> \
  --file build/export/ThirdHand.ipa \
  --version 0.1.0 \
  --build-number 2 \
  --platform ios \
  --wait
```

`--wait` polls until Apple finishes processing, which is usually 5–30 minutes for
a first build. Without it the command returns as soon as the bits are accepted and
the build shows as *Processing* in App Store Connect.

The wrapper does the same thing and gates on credentials first:

```sh
./Scripts/upload-testflight.sh build/export/ThirdHand.ipa
./Scripts/upload-testflight.sh --dry-run     # prints the asc command, uploads nothing
```

`fastlane ios beta` calls that wrapper after exporting. It fails before archiving
if credentials or the app id are missing, so a missing secret costs seconds rather
than a six-minute archive followed by a failed upload.

### Credentials

Resolution order, first match wins:

1. `ASC_KEY_ID` + `ASC_ISSUER_ID` (+ `ASC_KEY_PATH` for a CI runner) in the env
2. the machine's stored `asc` account (`asc auth list` shows it active)

| Variable | Purpose |
| --- | --- |
| `ASC_KEY_ID` | API key id (`38R6G5B784` for this team) |
| `ASC_ISSUER_ID` | Issuer UUID (`4e8ddd0a-9e6c-4877-ae9d-3f7168c02256`) |
| `ASC_KEY_PATH` | Path to the `.p8`. Never committed. |
| `THIRDHAND_ASC_APP_ID` | Numeric App Store Connect app id. Empty until the record exists. |
| `THIRDHAND_TEAM_ID` | Overrides the team id (defaults to `4QJ25Y85MX`) |
| `THIRDHAND_BETA_TESTERS` | Optional comma-separated emails for `fastlane ios groups` |

`fastlane/.env.example` lists them with no values. Copy it to `fastlane/.env`
(gitignored) or export them. The `.p8` gets written from a CI secret at job start
and never lands in the workspace as a tracked file.

Log in once on a new machine:

```sh
asc auth login --key-id 38R6G5B784 \
               --issuer-id 4e8ddd0a-9e6c-4877-ae9d-3f7168c02256 \
               --key-path /path/to/AuthKey_38R6G5B784.p8
```

---

## 5. Where builds land

| Artefact | Location | Committed? |
| --- | --- | --- |
| `.ipa` | `build/export/ThirdHand.ipa` | no — `build/` is gitignored |
| `.xcarchive` | `build/ThirdHand.xcarchive` | no |
| `.dSYM` | `build/ThirdHand.xcarchive/dSYMs/` | no |
| App Store Connect | uploaded build, visible in TestFlight | — |
| Builds listing | `asc builds list --app-id <APP_ID> --pretty` | — |

`build/`, `*.ipa` and `*.dSYM.zip` are all in `.gitignore`, and
`git ls-files | grep -E '\.p8$|\.env$|ipa$'` returns nothing.

---

## 6. TestFlight

### The app record does not exist yet

`asc` v0.18.2 has no app-creation subcommand (`asc apps` exposes only `list` and
`update`), and the App Store Connect REST API has no public create-app endpoint.
The record must be created once in the portal:

1. <https://appstoreconnect.apple.com/apps> → **My Apps** → **+** → **New App**
2. Platform **iOS**
3. Name **`Pulse — What Needs You`** (plain `Pulse` is taken — `APPSTORE-SETUP.md` §3)
4. Primary language **English (U.S.)**
5. Bundle ID **`Pulse` (`com.steveafrost.thirdhand`)**
6. SKU **`thirdhand-ios-001`**
7. Full Access → **Create**

Then record the numeric id (it is in the URL: `…/apps/<id>/…`) as
`THIRDHAND_ASC_APP_ID`.

If a browser session cookie is available, the private API can do it instead:

```sh
export ASC_IRIS_COOKIES=<cookie jar from a logged-in appstoreconnect session>
asc iris apps create --name "Pulse — What Needs You" --bundle-id com.steveafrost.thirdhand \
  --sku thirdhand-ios-001 --primary-locale en-US --platforms IOS --version 1.0
```

### Internal beta group

```sh
# 1. find the app id
asc apps list --pretty

# 2. create the internal group (idempotent in the fastlane lane)
asc testflight groups create --app-id <APP_ID> --name "Pulse Beta" --internal

# 3. list it
asc testflight groups list --app-id <APP_ID> --pretty

# 4. add an internal tester (must be a member of the App Store Connect team)
asc testflight testers add --beta-group-id <GROUP_ID> --email you@example.com \
  --first-name Steve --last-name Frost

# 5. confirm
asc testflight testers list --beta-group-id <GROUP_ID> --pretty
```

Or all at once:

```sh
THIRDHAND_ASC_APP_ID=<APP_ID> THIRDHAND_BETA_TESTERS=you@example.com fastlane ios groups
```

That lane is idempotent: it looks for a group named `Pulse Beta` first and
only creates it when absent. No tester address is ever invented — with
`THIRDHAND_BETA_TESTERS` unset it prints the click-path and adds nobody.

**Internal vs external:** internal testers are App Store Connect team members and
need no App Review or beta review. External testers do. Pulse Beta is internal, so
the first build is testable within minutes of processing.

### After the upload

```sh
asc builds list --app-id <APP_ID> --pretty          # find the build id, wait for VALID
asc builds add-beta-group --build-id <BUILD_ID> --beta-group-id <GROUP_ID>
asc builds update-beta-notes --build-id <BUILD_ID> --locale en-US \
  --notes "Board ordering, Done/Snooze stickiness, snooze expiry, quick actions, closed review, widget, permission flow."
```

Export compliance should already be satisfied — `ITSAppUsesNonExemptEncryption`
is `false` in `project.yml` and is present in the exported `Info.plist`. If Apple
still asks, set it explicitly:

```sh
asc builds set-encryption-compliance --build-id <BUILD_ID> --uses-non-exempt-encryption false
```

The full step-by-step, with the "What to Test" text for build 1, is in
[`TESTFLIGHT.md`](TESTFLIGHT.md).

---

## 7. Rolling back a build

TestFlight builds cannot be deleted, only expired. To stop testers seeing one:

1. App Store Connect → your app → **TestFlight** → select the build →
   **Expire Build**. It drops out of the group immediately.
2. Fix forward and upload a higher build number. Never re-upload the same number:
   TestFlight will reject it.

If a build reached the App Store, a version cannot be pulled, only superseded:
submit a new version with the fix and request an expedited review if it is
urgent. Who to tell: the internal tester list in `Pulse Beta`.
