# App Store Connect & Developer Portal Setup — Third Hand iOS

Account-side plumbing for the first TestFlight upload. No Swift, no build, no upload.
Last updated by the provisioning pass on `main`.

Team ID (seed ID): `4QJ25Y85MX` — Apple ID `STEVEN ALLEN FROST`.

---

## 1. Identifiers created (done via API)

| Thing | Identifier | Resource ID | Status |
| --- | --- | --- | --- |
| App ID (main) | `com.steveafrost.thirdhand` | `UL473MF76P` | Registered by `asc` |
| App ID (widget) | `com.steveafrost.thirdhand.widgets` | `33GP8PGDGU` | Registered by `asc` |
| App ID (share) | `com.steveafrost.thirdhand.share` | `N8FQNRRQT2` | Registered by `asc` (M7.1) |
| App Group | `group.com.steveafrost.thirdhand` | — | **Not creatable via CLI** — portal only |
| iCloud container | `iCloud.com.steveafrost.thirdhand` | — | **Not creatable via CLI** — portal only |
| App Store app record | name TBD (see §3) | — | **Not creatable via CLI** — portal only |
| SKU (reserved) | `thirdhand-ios-001` | — | To use on app-record creation |

Both App IDs were created with `platform: ios`, which the API normalises to `UNIVERSAL`.
`seedID` is `4QJ25Y85MX` on both. Verify at any time:

```sh
asc bundle-ids list --identifier "com.steveafrost.thirdhand" --pretty
```

> Note: bare `asc bundle-ids list` is paginated to the first 20 rows and the Third Hand IDs do
> not appear in that page. Always pass `--identifier` when checking.

### Capabilities: not settable by this CLI

`asc` v0.18.2 has **no** capability, App Group or iCloud-container subcommand. The tests
below were run and returned these errors verbatim:

```
$ asc bundle-capabilities list
Error: 2 unexpected arguments: 'bundle-capabilities', 'list'
Usage: asc <subcommand>
  See 'asc --help' for more information.

$ asc app-groups list
Error: 2 unexpected arguments: 'app-groups', 'list'

$ asc icloud-containers list
Error: 2 unexpected arguments: 'icloud-containers', 'list'

$ asc capabilities list
Error: 2 unexpected arguments: 'capabilities', 'list'
```

So the capabilities in §2 must be enabled by hand.

---

## 2. Capabilities — portal steps (TODO)

Both bundle ids need **App Groups**; the main app additionally needs **iCloud**.

### 2a. Create the App Group — do this first

1. <https://developer.apple.com/account/resources/identifiers/list/appGroup> → **Identifiers → App Groups** → **+**
2. Register an App Group: Description `Third Hand`, Identifier `group.com.steveafrost.thirdhand` → **Continue** → **Register**

### 2b. Create the iCloud container

1. <https://developer.apple.com/account/resources/identifiers/list/cloudContainer> → **Identifiers → iCloud Containers** → **+**
2. Description `Third Hand`, Identifier `iCloud.com.steveafrost.thirdhand` → **Continue** → **Register**

### 2c. Main app — `com.steveafrost.thirdhand`

1. <https://developer.apple.com/account/resources/identifiers/list> → **Identifiers → App IDs** → click `Third Hand` (`com.steveafrost.thirdhand`)
2. Under **Capabilities**, tick:
   - **App Groups** → **Configure** → tick `group.com.steveafrost.thirdhand` → **Continue**
   - **iCloud** → **Configure** → *Enable iCloud*; tick **CloudKit**? **NO**; tick **iCloud Documents** → **Continue**.
     Under *iCloud Containers*, tick `iCloud.com.steveafrost.thirdhand`.
     (The app uses `com.apple.developer.icloud-services = CloudDocuments`, i.e. ubiquity
     documents, not CloudKit. Do not enable CloudKit.)
3. **Save**. The App ID row must show App Groups and iCloud as *Enabled*.

### 2d. Widget — `com.steveafrost.thirdhand.widgets`

1. Same **App IDs** list → click `Third Hand Widgets` (`com.steveafrost.thirdhand.widgets`)
2. Tick **App Groups** → **Configure** → tick `group.com.steveafrost.thirdhand` → **Continue**
3. **Save**. No iCloud capability on the widget. Do **not** tick Push or In-App Purchase —
   neither is needed for the MVP.

Entitlements already declared in `project.yml` and matching the above:

```yaml
# Third Hand target
com.apple.developer.icloud-container-identifiers: [iCloud.com.steveafrost.thirdhand]
com.apple.developer.icloud-services: [CloudDocuments]
com.apple.developer.ubiquity-container-identifiers: [iCloud.com.steveafrost.thirdhand]

# ThirdHandWidgets target
com.apple.security.application-groups: [group.com.steveafrost.thirdhand]
```

---

## 3. App record — portal steps (TODO)

### The name "Third Hand" is TAKEN

An exact-title match exists on the App Store: **`Third Hand`** by `ua.com.pulse.app`
(present in the US, GB, CA, AU, DE, FR and JP storefronts, plus separate "Third Hand"
titles from other developers). The name `Third Hand` cannot be used as the App Store name.

Ranked alternatives (all verified **free** — no exact-title match in US or GB):

1. **`Third Hand — What Needs You`** — recommended. Keeps the brand, states the value prop,
   and is the closest to the product line "what needs me right now?".
2. **`Third Hand Board`** — short, matches the Now/Next/Later/Nice-to-Know board metaphor.
3. **`Third Hand Daily`** — short, works if the product leans into the daily-review rhythm.

Use the full name in the App Store listing; the Home Screen display name can stay
`Third Hand` (`CFBundleDisplayName`) — that is independent of App Store name uniqueness.

### Create it

1. <https://appstoreconnect.apple.com/apps> → **My Apps** → **+** → **New App**
2. Platform **iOS**
3. Name: **`Third Hand — What Needs You`** (or #2/#3 if that is rejected)
4. Primary Language: **English (U.S.)**
5. Bundle ID: **`Third Hand` (`com.steveafrost.thirdhand`)** — appears in the picker now that §1 is done
6. SKU: **`thirdhand-ios-001`**
7. User Access: Full Access → **Create**

Record the resulting numeric **Apple ID / app id** here once created: `_____________`

### Why the CLI could not do it

```
$ asc apps create --name "Third Hand" --bundle-id com.steveafrost.thirdhand --sku thirdhand-ios-001
Error: Unknown option '--name'
Usage: asc apps <subcommand>

$ asc apps --help
SUBCOMMANDS:
  list                    List all apps
  update                  Update app-level metadata (currently: content rights declaration)
```

There is no public-API app-creation endpoint. The only CLI route is the private API,
which needs a browser cookie session that this environment does not have:

```
$ asc iris apps create --name "Third Hand" --bundle-id com.steveafrost.thirdhand --sku thirdhand-ios-001
Error: No App Store Connect cookies found. Log in to appstoreconnect.apple.com in your browser, or set ASC_IRIS_COOKIES environment variable.
```

If you want to try the CLI instead of clicking: log in to App Store Connect in Safari,
set `ASC_IRIS_COOKIES`, then
`asc iris apps create --name "Third Hand — What Needs You" --bundle-id com.steveafrost.thirdhand --sku thirdhand-ios-001 --primary-locale en-US --platforms IOS --version 1.0`.

---

## 4. Metadata — API-settable once the app record exists

All of these need the numeric app id and an App Info id. Once §3 is done:

```sh
asc app-infos list --app-id <APP_ID> --pretty        # gives app-info-id
asc apps update --app-id <APP_ID> \
  --content-rights-declaration DOES_NOT_USE_THIRD_PARTY_CONTENT
asc app-infos update --app-info-id <APP_INFO_ID> \
  --primary-category PRODUCTIVITY --secondary-category BUSINESS
asc age-rating update --declaration-id <DECLARATION_ID> ...   # see §4.3
```

### 4.1 Category — verified valid

`PRODUCTIVITY` and `BUSINESS` are both real, iOS-supported category ids. Confirmed:

```
$ asc app-categories get --category-id PRODUCTIVITY
{"id":"PRODUCTIVITY","platforms":["IOS","MAC_OS","TV_OS","VISION_OS"]}
$ asc app-categories get --category-id BUSINESS
{"id":"BUSINESS","platforms":["IOS","MAC_OS","TV_OS","VISION_OS"]}
```

Caveat: `asc app-categories list` returns 70 rows and does **not** include
`PRODUCTIVITY` (it does include `BUSINESS`). `get` resolves it fine, so use
`get` to validate, not `list`. Set primary = `PRODUCTIVITY`, secondary = `BUSINESS`.
`PRODUCTIVITY` has no subcategories, so leave `--primary-subcategory-*` unset.

### 4.2 Content rights

`DOES_NOT_USE_THIRD_PARTY_CONTENT` — the app displays only the user's own calendar,
reminders and (later) their own mail. No licensed third-party content.

### 4.3 Age rating — answers (lands at 4+)

Set every boolean to `false` and every intensity to `NONE`:

| Field | Value |
| --- | --- |
| `--advertising` | false |
| `--gambling` | false |
| `--gambling-simulated` | NONE |
| `--loot-box` | false |
| `--messaging-and-chat` | false |
| `--user-generated-content` | false |
| `--unrestricted-web-access` | false |
| `--parental-controls` | false |
| `--age-assurance` | false |
| `--health-or-wellness-topics` | false |
| `--alcohol-tobacco-drugs` | NONE |
| `--contests` | NONE |
| `--guns-weapons` | NONE |
| `--medical-treatment` | NONE |
| `--profanity` | NONE |
| `--sexual-content-graphic` | NONE |
| `--sexual-content` | NONE |
| `--horror-fear` | NONE |
| `--mature-suggestive` | NONE |
| `--violence-cartoon` | NONE |
| `--violence-realistic` | NONE |
| `--violence-realistic-prolonged` | NONE |
| `--age-rating-override` | NONE |
| `--korea-age-rating-override` | NONE |

Expected result: **4+** / `FOUR_PLUS`. No `--kids-age-band` (not a Kids Category app).
Justification: the app shows only the user's own data, has no user-generated content,
no web browsing, no ads, no chat, no gambling.

### 4.4 Support & marketing URL

- **Support URL**: `https://github.com/steveafrost/thirdhand-ios` (verified reachable, HTTP 200;
  the repo remote is exactly this). This is the existing, correct destination — no better
  Third Hand-specific site exists yet.
- **Marketing URL**: optional. Use the same GitHub URL until a landing page exists.
- **Privacy Policy URL**: still required for submission even when zero data is collected.
  Not settable before the app record; supply a URL before submitting for review.

---

## 5. App Privacy — answers to paste in

**Data Not Collected.**

The app collects no data. Everything (calendar, reminders, items, done/snooze state) stays
on the device and syncs only through the user's own private iCloud container
(`iCloud.com.steveafrost.thirdhand`). The developer operates no server and receives nothing.
Third-party SDKs: none.

Portal steps (App Store Connect → your app → **App Privacy** → **Get Started**):

1. "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app**
2. **Save** / **Publish**

That single answer is the whole questionnaire — no data types to tick.

Why not via CLI: `asc` v0.18.2 exposes no App Privacy / data-collection subcommand:

```
$ asc app-privacy get
Error: 2 unexpected arguments: 'app-privacy', 'get'
```

Note: Apple still requires a **Privacy Policy URL** in App Store Connect even when the
answer is Data Not Collected.

---

## 6. Checklist

### Done via API

- [x] App ID `com.steveafrost.thirdhand` registered — resource id `UL473MF76P`
- [x] App ID `com.steveafrost.thirdhand.share` registered — resource id `N8FQNRRQT2`

> **Share extension provisioning.** `com.steveafrost.thirdhand.share` needs the
> **App Groups** capability (`group.com.steveafrost.thirdhand`), which `asc` cannot
> add. The first archive that includes `ThirdHandShare` must therefore run with
> `-allowProvisioningUpdates` so Xcode can register the capability itself; without
> it the archive fails with *"doesn't include the App Groups capability"*.
> `fastlane/Fastfile` already passes the flag — only hand-run `xcodebuild archive`
> commands need it.
- [x] App ID `com.steveafrost.thirdhand.widgets` registered — resource id `33GP8PGDGU`
- [x] Both App IDs on seed `4QJ25Y85MX`, platform iOS/UNIVERSAL
- [x] Category ids `PRODUCTIVITY` + `BUSINESS` validated against the API
- [x] App Store name availability checked — `Third Hand` is taken; 3 alternatives verified free
- [x] Confirmed Apple Distribution certificate already exists (no new cert created)

### Still needs the portal

- [ ] Create App Group `group.com.steveafrost.thirdhand`
      — Identifiers → App Groups → **+**
- [ ] Create iCloud container `iCloud.com.steveafrost.thirdhand`
      — Identifiers → iCloud Containers → **+**
- [ ] Enable **App Groups** on `com.steveafrost.thirdhand` (tick the group)
      — Identifiers → App IDs → Third Hand → Capabilities → App Groups → Configure
- [ ] Enable **iCloud** on `com.steveafrost.thirdhand`, sub-option **iCloud Documents** only
      (not CloudKit), container `iCloud.com.steveafrost.thirdhand`
      — Identifiers → App IDs → Third Hand → Capabilities → iCloud → Configure
- [ ] Enable **App Groups** on `com.steveafrost.thirdhand.widgets` (tick the group)
      — Identifiers → App IDs → Third Hand Widgets → Capabilities → App Groups → Configure
- [ ] Create the app record (name `Third Hand — What Needs You`, SKU `thirdhand-ios-001`)
      — App Store Connect → My Apps → **+** → New App
- [ ] Set primary category `PRODUCTIVITY`, secondary `BUSINESS`
      — App Information → Category
- [ ] Set content rights = does not use third-party content — App Information
- [ ] Complete the age-rating questionnaire to land at **4+** — App Information → Age Rating
- [ ] Set App Privacy = **Data Not Collected** — App Privacy
- [ ] Add Support URL + Privacy Policy URL — App Store → App Information / version page

Nothing here creates a provisioning profile or a distribution certificate; that happens at
upload time and the existing `Apple Distribution: STEVEN ALLEN FROST (4QJ25Y85MX)` cert covers it.

---

## 7. Notes for Fastlane / CI

Credentials are referenced **by ID only** — no key material belongs in this repo.

| Item | Value |
| --- | --- |
| Issuer ID (API key) | `4e8ddd0a-9e6c-4877-ae9d-3f7168c02256` |
| Key ID (API key) | `38R6G5B784` |
| Key file | **not in repo** — supply the `.p8` at runtime via CI secret / `ASC_KEY_PATH` |
| Team / seed ID | `4QJ25Y85MX` |
| Distribution cert | `Apple Distribution: STEVEN ALLEN FROST (4QJ25Y85MX)` — already exists |
| SKU | `thirdhand-ios-001` |
| App ID (main) | `com.steveafrost.thirdhand` / portal resource `UL473MF76P` |
| App ID (widget) | `com.steveafrost.thirdhand.widgets` / portal resource `33GP8PGDGU` |
| App Group | `group.com.steveafrost.thirdhand` |
| iCloud container | `iCloud.com.steveafrost.thirdhand` |
| Numeric ASC app id | `TBD` — fill in after §3 |

`asc` auth is stored in `~/.asc/credentials.json` on this machine (do not copy it around).
A CI runner should instead export the key: `asc auth login` supports file-sourced keys, and
Fastlane can read the same issuer/key pair directly. Never commit `.p8`, `.p12`, or
`~/.asc/credentials.json`.

Suggested CI sequence once a build exists:
`xcodebuild archive` → `exportArchive` (automatic signing picks up the App Group + iCloud
entitlements from the portal) → `xcrun altool`/`asc builds upload` → TestFlight. Not run
here; there is no shipping code yet.

---

## 8. Environment facts recorded during this pass

- `asc` version 0.18.2, authenticated profile `tiptrack`, active, source `file`.
- No `ASC_IRIS_COOKIES` in the environment; the private API is therefore unavailable.
- Existing DISTRIBUTION certificates: `N5XNR96XV9`, `N74D4ZRCV9` (both `STEVEN ALLEN FROST`).
- No Provisioning Profiles exist yet for either Third Hand bundle id (`asc profiles list` returns `[]`).
