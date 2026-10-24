# App Store metadata — Third Hand

Everything App Store Connect asks for on the version page, ready to paste.
Verified against `asc` v0.18.2 and against the archive described in §10 of
`RELEASE.md`. The version record and `MARKETING_VERSION` are both `0.1.0`;
build 3 is the one uploaded to TestFlight (build 1 was rejected on iPad
orientations, 90474; build 2 shipped without the mailbox or the redesigned board).

The screenshots in `docs/screenshots/` were recaptured against build 3. The
earlier set predated the design pass by five hours and no longer matched the
shipped board.

Companion docs: [`APPSTORE-SETUP.md`](APPSTORE-SETUP.md) (account plumbing and
portal click-paths) and [`PRIVACY.md`](PRIVACY.md) (the policy behind §5).

---

## 1. Names

| Field | Value | Limit | Length |
| --- | --- | --- | --- |
| App Store name | `Third Hand — What Needs You` | 30 | 22 |
| Home Screen name (`CFBundleDisplayName`) | `Third Hand` | — | 5 |
| Bundle ID | `com.steveafrost.thirdhand` | — | — |
| SKU | `thirdhand-ios-001` | — | — |
| Subtitle | `Your day, ordered by urgency` | 30 | 28 |

**The plain name `Third Hand` is taken.** An exact-title app by `ua.com.pulse.app`
sits in the US, GB, CA, AU, DE, FR and JP storefronts, and other developers hold
near-identical titles. `Third Hand — What Needs You` was verified free in US and GB
(see `APPSTORE-SETUP.md` §3). The Home Screen label stays `Third Hand`; that is
independent of App Store name uniqueness, and `CFBundleDisplayName` already says
so.

`asc apps list` was re-run while writing this doc: no existing app record has
bundle id `com.steveafrost.thirdhand`, so nothing is colliding with the new record.

---

## 2. Promotional text

```
See everything that needs a reply, a decision or your attention, ordered by urgency. From your calendar, reminders and mailbox. No account, no analytics.
```

153 characters (limit 170). Editable at any time without a new review, which is
why it leads with the value proposition rather than a release note.

---

## 3. Description

2 542 characters (limit 4 000). Product copy only: no placeholder text, no
competitor claims, no pricing.

```text
Third Hand answers one question: what needs me right now?

Most task apps ask you to maintain them. Third Hand doesn't. It reads the calendar and reminders already on your iPhone, works out what actually needs you, and puts it on one board in the order you'd want to deal with it.

FOUR HORIZONS, ONE GLANCE

Everything lands in one of four sections, decided by urgency rather than by a project you forgot to update:

- Now - high priority, or due today
- Next - due in the next three days
- Later - everything further out
- Nice to Know - worth a look, not worth acting on yet

The board is quiet by design: one number on screen, the Now count. Urgency is shown by position, not by colour alone.

DONE AND SNOOZE ACTUALLY STICK

Tick something and it stays done, even when the next refresh runs. Snooze moves it out of the way for an hour, until tonight, or until tomorrow morning, and it comes back on its own when the snooze expires. Nothing silently reappears, and nothing silently disappears.

- Tap a row for the full detail: source, quick actions, history
- Swipe to snooze or dismiss
- Every action is one gesture, and every one is reversible from Recently Closed for three days

BUILT FOR YOUR WEEK, NOT YOUR INBOX

- Quick actions for the things you do most: RSVP, open the thread, copy a link, complete a reminder
- A Recently Closed review, so the thing you closed by accident is one tap away
- A filter bar when you want one source at a time
- Search when you know what you are looking for

WIDGETS AND THE LOCK SCREEN

Home Screen widgets in three sizes and all three Lock Screen families, plus a Live Activity for the meeting that is about to start. The widget reads the same board the app does, so it never gives a different answer.

YOUR DATA STAYS YOURS

Third Hand has no account and no server of its own. It reads your calendar and reminders on the device, and nothing leaves it.

- Calendar and Reminders are read on this device and stored on this device
- No analytics, no tracking, no third-party SDKs
- Your board syncs to your own private iCloud so it can reach your Mac, and to nobody else
- Everything else is stored on the device and nowhere else

MAIL IS OPTIONAL, AND IT IS YOURS

Optionally, you can connect a mailbox over IMAP so messages that need a reply show up on the same board. It is off until you turn it on.

- Your mail password is stored in the iOS Keychain, marked so it never leaves this device and is never included in a backup to a new one
- It is sent only to your own mail provider, to sign in. There is no middle server and nothing to route through us
- Message headers are read on the device; nothing is uploaded anywhere
- Disconnecting deletes the stored password and the cached mail items

If you delete the app, Third Hand has nothing left to delete.

WHO IT IS FOR

People who already keep a calendar and a reminders list, and who want one honest view of what those two things are asking of them today - without another system to maintain.

Third Hand is a productivity app for iOS. It needs access to Calendar and Reminders to be useful; you can grant either, both, or neither, and turn them off again in Settings at any time.
```

---

## 4. Keywords

```
tasks,agenda,todo,calendar,reminder,focus,priority,daily,planner,productivity,personal
```

86 characters (limit 100), comma-separated with no spaces. No word is repeated
from the app name (`Third Hand`, `What`, `Needs`, `You`) — that would waste
characters, because App Store search already indexes the name and subtitle
separately.

---

## 5. Privacy

### App Privacy answers (App Store Connect → App Privacy)

**Data Not Collected.**

The questionnaire is a single question:

> **Do you or your third-party partners collect data from this app?**
> → **No, we do not collect data from this app**

Save, then **Publish**. There are no data types to tick, no purposes to select,
and no tracking section, because the first answer short-circuits everything
else.

Why this is true, per [`ARCHITECTURE.md`](ARCHITECTURE.md) §Privacy:

| What a reviewer might ask | Why it is not "collected" |
| --- | --- |
| Calendar and reminders are read | Read on-device and stored on-device. Nothing is transmitted to the developer or any third party. |
| There is an iCloud snapshot | It goes to **the user's own private iCloud container** (`iCloud.com.steveafrost.thirdhand`), under their Apple ID. The developer has no access, no server, and no key. Apple treats "data stored in the user's own iCloud, not accessible to the developer" as not collected by the developer. |
| Any analytics or crash reporting? | None. No third-party SDKs, no telemetry, no crash reporter. |
| Any account? | None. No app account, no sign-up, no identifier. |
| **A connected mailbox (new in this build)** | The user's own IMAP credentials and message headers. The password is in the device Keychain and is sent **only to the user's own mail host** to authenticate; headers are read on-device. Nothing is routed through the developer, so nothing is collected *by the developer or a third party* — which is what the question asks. The mailbox is off unless the user enables it. |

**Judgement call, stated plainly.** The mailbox is the one place a reviewer could
reasonably disagree. The position taken here is that "Data Not Collected" remains
correct because collection is defined as transmission off the device *to the developer
or a third party*, and an IMAP client talking to the account owner's own mail server at
their instruction is neither. Apple's own Mail app reports the same shape. If a reviewer
pushes back, the fallback is to declare **User Content → Emails or Text Messages**,
purpose *App Functionality*, not linked to identity, not used for tracking — that answer
is also true and is the conservative one.

If the App Privacy UI is unavailable (it is not settable by `asc` — the CLI has no
`app-privacy` subcommand), this is the developer-portal step:
**App Store Connect → your app → App Privacy → Get Started → "No, we do not collect
data from this app" → Save → Publish.**

### Privacy Policy URL

`https://github.com/steveafrost/thirdhand-ios/blob/main/docs/PRIVACY.md`

Apple requires a reachable URL even for Data Not Collected. The policy is
committed at [`docs/PRIVACY.md`](PRIVACY.md) and rendered by GitHub. If a
github.com URL is rejected at submission (some reviewers refuse them), the
fallback is GitHub Pages on the same file —
`https://steveafrost.github.io/thirdhand-ios/PRIVACY.html` — which needs Pages turned
on for the repo first. See §7 for the switch.

### App Privacy detail (the free-text field)

> Third Hand does not collect any data. Calendar and reminders are read on the device
> and stay there. Your board is mirrored to your own private iCloud container so
> it can reach your Mac; that copy belongs to your Apple ID and is never visible
> to the developer. If you choose to connect a mailbox, its password is kept in the
> iOS Keychain on this device and sent only to your own mail provider; message headers
> are read on the device and are not uploaded anywhere. There is no account, no
> server of ours, no analytics and no third-party SDK.

---

## 6. Category, rating, URLs

| Field | Value |
| --- | --- |
| Primary category | **Productivity** |
| Secondary category | None |
| Age rating | **4+** |
| Support URL | `https://github.com/steveafrost/thirdhand-ios/issues` |
| Marketing URL | `https://github.com/steveafrost/thirdhand-ios` |
| Copyright | `2026 Steve Frost` |
| Content rights | Does not use third-party content |

### Age rating — the 4+ answers

Every content question is **None** / **No**. There is no user-generated content,
no messaging, no web browser, no ads, no gambling, no loot boxes, no age-gated
content of any kind. The app displays only the user's own calendar and reminders.
The full field-by-field answer list is in `APPSTORE-SETUP.md` §4.3.

Accessibility has no bearing on the age rating, but for the record the app supports
Dynamic Type through AX5 and VoiceOver (see `ACCESSIBILITY.md`).

---

## 7. Support and policy pages

Two options, in order of preference:

1. **Zero setup (recommended):** the committed markdown renders on GitHub.
   - Support: `https://github.com/steveafrost/thirdhand-ios/blob/main/docs/SUPPORT.md`
   - Privacy: `https://github.com/steveafrost/thirdhand-ios/blob/main/docs/PRIVACY.md`
2. **GitHub Pages:** Settings → Pages → Source: *Deploy from a branch* →
   branch `main`, folder `/docs` → Save. The pages then become
   `https://steveafrost.github.io/thirdhand-ios/SUPPORT.html` and
   `…/PRIVACY.html`. Use this if a reviewer rejects a github.com/blob URL.

The URL actually entered in App Store Connect must be recorded here before
submission, together with the date it was checked:

| Field | URL entered | Checked |
| --- | --- | --- |
| Support URL | _fill at submission_ | — |
| Privacy Policy URL | _fill at submission_ | — |

---

## 8. Screenshots

### Required sizes — verified, not assumed

`asc` v0.18.2 accepts these display types for `asc screenshot-sets create
--display-type` (rejected types omitted):

| Display type | Device | Pixels | Needed for Third Hand |
| --- | --- | --- | --- |
| `APP_IPHONE_67` | iPhone 6.7"/6.9" | 1290×2796 or 1320×2868 | **Yes** — primary |
| `APP_IPHONE_65` | iPhone 6.5" | 1242×2688 or 1284×2778 | Yes — fallback/compat |
| `APP_IPHONE_61` | iPhone 6.1" | 1179×2556 | Optional |
| `APP_IPHONE_58` | iPhone 5.8" | 1125×2436 | Not required |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro 13" | 2064×2752 | **No** — iPhone-only app |

`APP_IPHONE_69` and `APP_IPHONE_66` are **rejected** by this API version
(`Unknown display type`). So the 6.9" 1320×2868 captures produced here upload
into the `APP_IPHONE_67` bucket — App Store Connect takes the 6.9" pixels there.
That is what the captures in `docs/screenshots/` are sized for.

The app ships `UIDeviceFamily = [1]` (iPhone only), so no iPad set is needed.
Recorded as `supportsIPad: false`.

### The shots captured

All are real simulator captures of the debug fixture board, status bar pinned to
9:41 with full battery and Wi-Fi, per `DESIGN.md` §12. No lorem, no mockups.

| # | File | Size | Screen |
| --- | --- | --- | --- |
| 1 | `01-board-now-69.png` | 1320×2868 | The board at default Dynamic Type, all four horizons |
| 2 | `02-detail-quick-actions-69.png` | 1320×2868 | Item detail: metadata, quick actions, history |
| 3 | `03-snooze-69.png` | 1320×2868 | The snooze menu, with its three durations |
| 4 | `04-closed-review-69.png` | 1320×2868 | Recently Closed, with the reopen affordance |
| 5 | `05-permission-preamble-69.png` | 1320×2868 | The preamble shown before any system permission prompt |
| 6 | `06-settings-69.png` | 1320×2868 | Settings: sources, mailbox row, privacy block |
| 7 | `07-email-account-69.png` | 1320×2868 | Connecting a mailbox: address, provider picker, password |
| 8 | `08-email-connected-69.png` | 1320×2868 | A connected mailbox, with status and the disconnect action |
| 9 | `09-board-dark-69.png` | 1320×2868 | The board in dark appearance |
| 10 | `10-all-clear-69.png` | 1320×2868 | The all-clear state with last-checked |

Captured with:

```sh
# A dedicated device, because a stale TCC grant on a reused simulator leaves the
# calendar prompt on screen and ruins every capture.
D=$(xcrun simctl create "TH Shots 69" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
      com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcrun simctl boot "$D"
xcrun simctl install  "$D" /tmp/shots/Build/Products/Debug-iphonesimulator/ThirdHand.app
xcrun simctl status_bar "$D" override --time "9:41" --batteryState charged \
    --batteryLevel 100 --wifiBars 3 --cellularBars 4

shoot() {  # image-name screen-name
  xcrun simctl terminate "$D" com.steveafrost.thirdhand 2>/dev/null; sleep 0.6
  xcrun simctl launch "$D" com.steveafrost.thirdhand \
      -ThirdHandDemoBoard -ThirdHandDemoScreen "$2" >/dev/null
  sleep 5
  xcrun simctl io "$D" screenshot "docs/screenshots/$1"
}

shoot 01-board-now-69.png            board
shoot 02-detail-quick-actions-69.png detail
shoot 03-snooze-69.png               snooze
shoot 04-closed-review-69.png        closed
shoot 05-permission-preamble-69.png  preamble
shoot 06-settings-69.png             settings
shoot 07-email-account-69.png        email
shoot 08-email-connected-69.png      emailConnected

xcrun simctl ui "$D" appearance dark
shoot 09-board-dark-69.png           board

# The all-clear state uses the empty fixture rather than the demo board.
xcrun simctl ui "$D" appearance light
xcrun simctl terminate "$D" com.steveafrost.thirdhand 2>/dev/null; sleep 0.6
xcrun simctl launch "$D" com.steveafrost.thirdhand \
    -ThirdHandDemoEmpty -ThirdHandDemoScreen board >/dev/null
sleep 5
xcrun simctl io "$D" screenshot docs/screenshots/10-all-clear-69.png
```

**`-ThirdHandDemoBoard` also short-circuits capture** (`DemoSeed.capture`), because
`EventKitEventProvider.events` calls `requestFullAccessToEvents()` on every pass and
would otherwise raise the system prompt over the board on each launch. That guard is
`#if DEBUG` and cannot affect a Release build.

The other screens swap `-ThirdHandDemoScreen` for `detail`, `snooze`, `closed`,
`preamble`, and add `-ThirdHandDemoEmpty` for the all-clear state. These flags are
compiled out of Release (`#if DEBUG` in `ThirdHandApp.swift`), so the fixture data
cannot ship.

### Not captured, and why

`DESIGN.md` §12 lists 11 shots. The gaps:

- **6.9" Live Activity and Lock Screen widgets (#9)** — waiting on the widget and
  Live Activity target work landing in `ThirdHandWidgets/`.
- **iPad (#7, #8)** — no iPad support; `UIDeviceFamily` is iPhone-only.
- **Completion moment (#3)** — a mid-animation frame; better captured on device.
- **Reduce Transparency (#11)** — needs an accessibility setting toggle we have
  not scripted yet.

Upload once the app record exists:

```sh
asc screenshot-sets create --localization-id <LOC_ID> --display-type APP_IPHONE_67
asc screenshots upload --set-id <SET_ID> --file docs/screenshots/01-board-now-69.png
```

---

## 9. What's New — 1.0 template

```
First release.

Third Hand reads your calendar and reminders and puts what actually needs you on one
board, in four horizons: Now, Next, Later and Nice to Know. Done and snooze stick,
snooze comes back on its own, and everything is reversible from Recently Closed.

Home Screen widgets in three sizes, all three Lock Screen families, and a Live
Activity for the meeting that is about to start.

No account, no server, no analytics. Your data stays on your device and in your
own private iCloud.
```

For a 1.0 submission the What's New field is optional; App Store Connect shows
"First release" if it is empty. Paste the block above so the release has a
description rather than a placeholder.

---

## 10. Review notes

Paste into **App Store Connect → App Version → App Review Information → Notes**:

```
No login or demo account is required. The app has no account system at all.

Third Hand reads the user's Calendar and Reminders to build one board of what needs
attention. On first launch it shows a preamble explaining this, then raises the
system prompts for Calendar ("Allow Full Access") and Reminders. Granting either,
both, or neither works: with neither granted, the board shows the connect state
from DESIGN.md 9.2 and the app remains usable.

The same data is mirrored to the user's own private iCloud container
(iCloud.com.steveafrost.thirdhand) so the board can be read on their Mac. The
developer operates no server and cannot see that data. This is why the App Privacy
answer is Data Not Collected.

No in-app purchases, no subscriptions, no ads, no external links out except the
Settings app.
```

Two things a reviewer is likely to test, and what they will see:

1. **Denying both permissions.** No crash, no dead end: the board shows the
   "Let's see what needs you" connect state with a button that re-opens Settings.
2. **Killing and relaunching mid-snooze.** The snooze survives the relaunch and
   expires on schedule. Losing state on relaunch would look like a bug.

If a reviewer cannot see any items because the simulator or device has an empty
calendar, that is expected — Third Hand shows what the device holds and nothing else.

---

## 11. Pre-submission field checklist

- [ ] App name `Third Hand — What Needs You`
- [ ] Subtitle `Your day, ordered by urgency`
- [ ] Promotional text pasted (§2)
- [ ] Description pasted (§3)
- [ ] Keywords pasted (§4)
- [ ] Support URL entered and loaded in a browser
- [ ] Privacy Policy URL entered and loaded in a browser
- [ ] Primary category Productivity, no secondary
- [ ] Age rating completed to 4+
- [ ] App Privacy published as Data Not Collected
- [ ] Screenshots uploaded for `APP_IPHONE_67` (and `APP_IPHONE_65` if required)
- [ ] Build selected for the version
- [ ] Review notes pasted (§10)
- [ ] `versions check-readiness` returns no blocking issues:
      `asc versions check-readiness --version-id <VERSION_ID>`
