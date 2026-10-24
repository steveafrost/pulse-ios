# TestFlight — Third Hand Beta

The internal TestFlight setup for Third Hand: the group, who is in it, how a build gets
there, and what testers should do with it.

**Current state: build uploaded and processed.** The app record, internal group
and tester all exist. The last unverified link is the build's membership of the
group, which `asc` gives no way to read back.

Status as of 24 October 2026:

| Prerequisite | State |
| --- | --- |
| API key authenticated for team `4QJ25Y85MX` | done — key `38R6G5B784` |
| Bundle IDs registered (`…thirdhand`, `…thirdhand.widgets`, `…thirdhand.share`) | done — `3SV5SH94CF`, `8UHD7M7N6D`, `9NL57L5636` |
| App Groups + iCloud container entitlements in the archive | done — verified in the exported `.ipa` |
| App Store Connect app record | done — **`6826457943`**, SKU `thirdhand-ios-001` |
| Internal group `Third Hand Beta` | done — `db830c96-822f-404b-a867-905261424a1b` |
| Internal tester | done — `hello@steveafrost.com` |
| Build uploaded and processed | done — `0.1.0` (**2**), `processingState: VALID` |
| Build attached to the beta group | **not verified** — see below |
| Version string matches the binary | done — record and `MARKETING_VERSION` are both `0.1.0` |
| Build linked to the version | **no** — portal step; blocks App Store submission, not TestFlight |

### The one unverified step

`asc builds add-beta-group` exits 0 and prints nothing, twice, and `asc` exposes
no read-back for a build's groups. The build is processed and the group has a
tester, but whether the build is *in* the group has not been observed. Check the
TestFlight tab: if the build is listed under "Third Hand Beta", this row is done.

### Version string

The version record was created as `1.0` while the binary is `0.1.0`. The record
now reads `0.1.0` too, so `project.yml`'s `MARKETING_VERSION` stays the single
source of truth and the uploaded build 2 still belongs to this version — no
rebuild or re-upload was needed. Pre-1.0 is the honest label for a first beta.

### The build is not linked to the version (App Store only)

`asc versions check-readiness` reports `buildCheck.linked: false`. `asc` v0.18.2
has no subcommand that links a build to a version, so this is a portal step.

It does **not** block TestFlight: testers get builds through the beta group, not
the version record. It does block **App Store submission** — pick the build under
the version's "Build" section before submitting for review.

---

## 1. Unblock: create the app record (portal, once)

`asc` cannot do this. There is no create-app endpoint in the public v1 API, and
`asc apps` in 0.18.2 exposes only `list` and `update`:

```console
$ asc apps list | jq '.data | length'
10
$ asc apps list | jq -r '.data[].bundleId' | grep -c pulse
0
```

Ten apps are in the account and none is Third Hand. So:

1. Open <https://appstoreconnect.apple.com/apps>
2. **My Apps** → **+** → **New App**
3. Fill exactly:

   | Field | Value |
   | --- | --- |
   | Platform | iOS |
   | Name | `Third Hand — What Needs You` |
   | Primary Language | English (U.S.) |
   | Bundle ID | `Third Hand` (`com.steveafrost.thirdhand`) |
   | SKU | `thirdhand-ios-001` |
   | User Access | Full Access |

4. **Create**

The name field will reject plain `Third Hand` — it is already held by another
developer. `Third Hand — What Needs You` was confirmed available; see
[`APPSTORE-SETUP.md`](APPSTORE-SETUP.md) §3.

Then copy the numeric id out of the URL (`…/apps/<ID>/…`) and record it:

```sh
echo "THIRDHAND_ASC_APP_ID=<ID>" >> fastlane/.env    # gitignored; see .env.example
```

Confirm it landed:

```sh
asc apps list --pretty | grep -A2 pulse
```

---

## 2. Create the internal group

Internal groups are the right choice for a first beta: testers are App Store
Connect team members, so there is **no Beta App Review** and no build review
before it appears. External testers need both, which delays the first build by
days.

```sh
# one command, idempotent, creates the group only if it is missing
THIRDHAND_ASC_APP_ID=<ID> fastlane ios groups
```

Or by hand:

```sh
asc testflight groups create --app-id <ID> --name "Third Hand Beta" --internal
asc testflight groups list   --app-id <ID> --pretty
```

Expected result — `isInternalGroup: true`, and the group is attached to no builds
until one is uploaded:

```json
{
  "data": {
    "id": "<GROUP_ID>",
    "name": "Third Hand Beta",
    "isInternalGroup": true
  }
}
```

### Why "Third Hand Beta" and not "Third Hand Internal"

The name shows in the TestFlight app under the app icon. `Third Hand Beta` reads as a
product stage; `Third Hand Internal` reads as a team. Either works technically; the
fastlane lane looks for the literal string `Third Hand Beta`, so if you rename it,
rename it in `fastlane/Fastfile` too (`groups` lane).

---

## 3. Invite testers

Internal testers must already be on the App Store Connect team (Users and Access).
You cannot invite an arbitrary address as an internal tester.

```sh
# per tester
asc testflight testers add \
  --beta-group-id <GROUP_ID> \
  --email someone@example.com \
  --first-name Ada --last-name Lovelace

# or in bulk
THIRDHAND_ASC_APP_ID=<ID> THIRDHAND_BETA_TESTERS="a@example.com,b@example.com" fastlane ios groups

# confirm
asc testflight testers list --beta-group-id <GROUP_ID> --pretty
```

No address is hardcoded anywhere in this repo. With `THIRDHAND_BETA_TESTERS` unset the
lane adds nobody and prints the click-path instead.

Each tester gets an Apple email inviting them to test, and must accept it once.
Then: **TestFlight app → Third Hand → Install**. Builds then update automatically.

**Tester list** (fill in as people are added — nothing is invented here):

| Name | Email | Added | Accepted |
| --- | --- | --- | --- |
| _none yet_ | — | — | — |

---

## 4. Getting a build into the group

Once §1 is done, this is the whole pipeline:

```sh
fastlane ios beta
```

That fails fast if `THIRDHAND_ASC_APP_ID` or credentials are missing, otherwise:
bump → generate → archive → export → upload. Processing takes 5–30 minutes.

Then attach the build and write the notes:

```sh
asc builds list --app-id <ID> --pretty            # wait for processingState VALID
asc builds add-beta-group --build-id <BUILD_ID> --beta-group-id <GROUP_ID>
asc builds update-beta-notes --build-id <BUILD_ID> --locale en-US --notes "$(cat <<'TXT'
Board ordering, Done and Snooze stickiness, snooze expiry, quick actions,
Recently Closed, and the permission flow.
TXT
)"
```

`add-beta-group` is idempotent: re-running it is safe. It prints nothing and
returns exit 0 whether or not the build was already in the group, so success
output is not evidence — check the TestFlight tab instead.

### What to test — build 2 (0.1.0, build 2)

Paste into the build's Test Information → What to Test:

```
Thanks for testing the first Third Hand build. Five things matter most:

1. BOARD ORDER. Items should be grouped Now / Next / Later / Nice to Know and
   ordered by urgency inside each group. Does the order match your intuition
   about what you would do first?

2. DONE STICKS. Tick an item, then pull to refresh. It must stay done. If it
   comes back, that is the bug I most want to hear about.

3. SNOOZE COMES BACK. Snooze something for an hour. It should leave the board and
   return on its own when the hour is up — including if you kill the app.

4. CLOSED IS RECOVERABLE. Everything you close should appear under the clock icon
   (Recently Closed) for three days and be reopenable.

5. THE PERMISSION FLOW. Fresh install, deny calendar, then grant it from the
   preamble. Nothing should dead-end.

Known gaps: no iPad layout, and the Lock Screen widgets are still in progress.
```

---

## 5. Reading a build's status

| Question | Command |
| --- | --- |
| Has Apple finished processing? | `asc builds list --app-id <ID> --pretty` → `processingState: VALID` |
| What failed? | `asc builds uploads --app-id <ID> --pretty` → look for `INVALID` state |
| Is the build in the group? | `asc builds list --app-id <ID> --pretty` → `betaGroups` |
| Will the version submit cleanly? | `asc versions check-readiness --version-id <VERSION_ID>` |
| Which build number is free? | `asc builds next-number --app-id <ID> --version 0.1.0 --platform ios` |

The state that bites is `INVALID`, usually from a version mismatch between the app
and the widget, or from an unsigned extension. Both are prevented here by
`project.yml` defining the version pair once and by the widget inheriting it — see
[`RELEASE.md`](RELEASE.md) §1.

---

## 6. Operational notes

- **Build numbers never repeat.** TestFlight permanently rejects a duplicate. Use
  `Scripts/bump-build.sh` or `fastlane ios beta`; never hand-edit
  `CURRENT_PROJECT_VERSION` down.
- **Internal builds expire after 90 days.** Testers see a warning at 60. Re-upload
  rather than trying to renew.
- **A build cannot be deleted,** only expired (TestFlight → the build → Expire
  Build). It disappears from the group at once.
- **Testers need the same Apple ID** for the App Store Connect team and the
  TestFlight app, or the invitation will not resolve.
- **Testers cannot use a build until the export compliance question is answered.**
  `ITSAppUsesNonExemptEncryption = false` is set in `project.yml`, so it is
  answered automatically. If a build still shows "Missing Compliance":
  `asc builds set-encryption-compliance --build-id <BUILD_ID> --uses-non-exempt-encryption false`.

---

## 7. Checklist to first tester

- [ ] App record created, `THIRDHAND_ASC_APP_ID` recorded (§1)
- [ ] Internal group `Third Hand Beta` created (§2)
- [ ] `fastlane ios beta` succeeded, upload accepted
- [ ] Build reached `processingState: VALID`
- [ ] Build attached to the group
- [ ] "What to Test" notes set for build 2
- [ ] At least one internal tester invited and accepted
- [ ] Tester installed from TestFlight and saw a populated board
- [ ] Feedback route agreed (issues on GitHub, or email — see [`SUPPORT.md`](SUPPORT.md))
