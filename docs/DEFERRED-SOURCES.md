# Deferred capture sources

Why Third Hand captures less than it declares, and what it would take to capture the rest.

## The current, honest position

`Source` declares six values (`ThirdHandCore/Sources/ThirdHandCore/Models/Enums.swift:16`):
`slack`, `gmail`, `calendar`, `github`, `docs`, `other`.

Of those, **`calendar`, `reminders` and now `gmail` pull data autonomously**. Mail is
read over **IMAP with an app-specific password held in the Keychain** — see
[Gmail / IMAP below](#gmail--imap--implemented-no-oauth). Slack, GitHub and Docs still
have **no OAuth application registered and no way to authenticate**. A source that tried
to call those APIs today would fail to authenticate and return nothing — and a source
that quietly returns nothing makes the board *look* complete while being blind, which is
worse than an absent source.

So instead of shipping three clients that cannot work, M7.1 shipped:

**`SharedLinkSource`** — the user shares a Slack thread, a GitHub PR or a Gmail
message into Third Hand via the `ThirdHandShare` app extension, and it becomes an item. This is
real, on-device, and requires no credentials. Its classification lives in
`Classifier.classifySharedLink` (`Classifier.swift:131`):

| What was shared | kind | priority |
| --- | --- | --- |
| Slack, text contains a decision phrase ("should we", "sign off", "vote on") | `decision` | normal |
| Slack, text contains a question mark | `reply` | normal |
| Slack, anything else or no text | `followup` | normal |
| GitHub pull request (`/pull/<n>`) | `review` | normal |
| Gmail message | `reply` | normal |
| Anything else | `fyi` | low |

The rule is never "return nothing": a share the user made deliberately must appear,
even when Third Hand cannot tell what it wants. An unknown host becomes `fyi` — information,
not a task.

**Its ceiling is exactly what the user shared.** It cannot see an unshared Slack
mention or a PR awaiting your review. (Unread Gmail is now covered by `EmailSource`.)

## What each deferred source would add

### GitHub — the highest value per unit of work

**Would add:** PRs where your review is requested, issues assigned to you, your own PRs
with failing checks or unaddressed review comments, and mentions.

**Why it is the best first integration:** PR review requests are exactly the shape Third Hand
is built for — a `review` kind with a real deadline, real participants, and an obvious
done action. GitHub also has the most pleasant auth story for a personal app.

**What it needs:**
- A **GitHub App** (preferred over OAuth App: finer scopes, installable, no user token
  to store). Minimum scopes: `pull_requests:read`, `issues:read`, plus the
  `checks:read` permission for CI state.
- Auth flow: device flow is acceptable for v1.1 and avoids a redirect URI entirely,
  which matters because Third Hand has no server.
- Token storage: **Keychain**, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — never
  UserDefaults, never the app group (the widget does not need it).
- Poll interval: 5–15 min behind `BGAppRefreshTask`, with ETag/conditional requests so
  a quiet poll costs almost nothing.
- Endpoints: `GET /issues?filter=assigned`, `GET /pulls?state=open` +
  `review-requested:@me` search, `GET /repos/{o}/{r}/pulls/{n}/reviews`.
- Identity: `github:pr:<owner>/<repo>#<n>` and `github:issue:<owner>/<repo>#<n>`, following
  `ItemIdentity`'s existing template, and stable across title edits.

### Gmail / IMAP — implemented, no OAuth

**Status: implemented and wired in.** `EmailSource`
(`ThirdHandCore/Sources/ThirdHandCore/Capture/EmailSource.swift`), with `IMAPClient`,
`TLSIMAPTransport`, `KeychainSecretStore`, `EmailAccount` and `EmailClassifier`, is
constructed in `ThirdHandApp.capture(store:)` alongside the EventKit sources, so it runs
in every real capture pass. With no mailbox saved it throws `CaptureError.denied(.gmail)`
— the board's "connect a mailbox" state — rather than returning an empty list that would
look like a healthy, quiet inbox.

**Verified against a real server; not yet against a real mailbox.** The TLS handshake,
greeting and live line framing were exercised against `imap.gmail.com` by
`TLSIMAPTransportLiveTests` (opt in with `THIRDHAND_LIVE_IMAP=1`). Authentication and
everything after it have not run against a live mailbox — see the verification table
below.

**What it adds:** every **unread** message in `INBOX` as an item, classified, with no
share-sheet action required. This is the "thread awaiting your reply" column the
share-sheet source could only ever approximate.

**Why IMAP and not the Gmail API.** The Gmail API path below is still the *better*
integration long-term and is still blocked on paperwork that is not engineering:
`gmail.readonly` is a restricted scope, so an unverified app is capped at 100 test
users, and while unverified a refresh token expires after 7 days — which for a
personal app with no server means a user re-authorising weekly. **IMAP with an
app-specific password sidesteps all of it.** It needs one credential the user
generates in five clicks, that Google can revoke independently of the account
password, and that never leaves the device.

**What is deliberately not claimed:**
- **No OAuth.** There is no Google Cloud project, no client id, no consent screen, and
  no token refresh. If OAuth is ever added, it replaces `EmailCredentials` and leaves
  `IMAPClient` untouched.
- **Not Gmail-specific.** `EmailAccount` takes any IMAPS host and port. Gmail is the
  convenience initialiser (`EmailAccount.gmail(username:)`), not a special case.
- **Attachments and bodies are not read.** One `FETCH` per message, headers only
  (`BODY.PEEK[HEADER.FIELDS (FROM TO CC SUBJECT DATE MESSAGE-ID REFERENCES IN-REPLY-TO)]`).
  `BODY.PEEK` — never `BODY[...]` — so a capture pass can never mark mail as read.
- **No `IDLE`.** Capture is poll-on-refresh, like every other source.

**Classification** (`EmailClassifier.classify`), in precedence order:

| Signal | kind | priority |
| --- | --- | --- |
| deadline phrase in the subject ("due Friday", "EOD") | `deadline` | high |
| decision phrase in the subject ("should we", "sign off") | `decision` | normal |
| the user is the sole `To`+`Cc` recipient and the message is not a reply | `reply` | normal |
| a question mark in the subject | `reply` | normal |
| anything else | `followup` | normal |

**A direct unread message is never `fyi` and never `low`.** That is asserted as an
invariant over a cross-product of subjects, recipient sets and reply flags in
`EmailClassificationTests.neverFYI`. Filing unread, personally-addressed mail under
"Nice to Know" would be the silently-blind board wearing a smile.

**Identity:** `gmail:message:<rfc822 Message-ID>`, matching the row `ItemIdentity`
already documented for shared mail — so a message both shared *and* received unread
is one card, not two. A message with no `Message-ID` (some mailers omit it) falls back
to `gmail:message:uid:<n>`, which is stable for as long as the message is unread in
that mailbox, i.e. the item's whole lifetime. The account is deliberately not part of
the id: the same list message delivered to two mailboxes is one message.

**Caps and omissions, stated rather than hidden:** at most
`IMAPClient.defaultLimit` (200) messages per pass, applied to the *oldest* end of
`UID SEARCH UNSEEN` — a thousand-message backlog costs the user nothing they were
going to act on today. No `window` filter: unread is unread.

**Operational honesty.** Missing configuration, a missing Keychain secret and a
rejected `LOGIN` all throw `CaptureError.denied(.gmail)`, which the engine reports as a
**paused source** with a fix ("connect a mailbox"). Socket, TLS and protocol failures
throw `CaptureError.underlying`. Only a genuinely empty inbox returns `[]`.

**Now verified against a live server** by `TLSIMAPTransportLiveTests`, which run when
`THIRDHAND_LIVE_IMAP=1` is set and are skipped otherwise so CI needs no network:

```sh
cd ThirdHandCore && THIRDHAND_LIVE_IMAP=1 swift test --filter TLSIMAPTransportLiveTests
```

**Any provider that accepts `LOGIN` over implicit TLS works**, not just Gmail. The
screen offers iCloud, Gmail, Outlook, Yahoo and Fastmail presets and fills the host in;
"Other" takes any IMAP host. All five endpoints were checked to complete a TLS
handshake and answer an IMAP greeting, and each was checked to reject a deliberately
wrong password with `NO [AUTHENTICATIONFAILED]` — meaning `LOGIN` is understood, so an
iCloud ("Apple Mail") account authenticates through the same path as Gmail. A provider
offering only OAuth would need a different client; none of these do.

| Property | How it is proven |
|---|---|
| TLS handshake completes | `open` returns a session against `imap.gmail.com:993` |
| Greeting is real IMAP | the greeting is read and must be `* OK` / `* PREAUTH` |
| Byte framing over a live socket | `A1 CAPABILITY` is sent and a tagged reply is read back line by line |
| Host-name verification is on | an IP endpoint for the same server is refused (`NWError -9808`) |
| Close is safe twice | no double-resume trap on the failure path |

The host-name test was checked for vacuity rather than assumed: with
`set_peer_authentication_required(_, false)` mutated in, that test **fails** because the
connection opens. An earlier draft used `wrong.host.badssl.com` and passed even with
verification disabled — the host closes the connection for unrelated reasons — so it was
replaced. The framing and handshake tests were likewise measured against the mutation to
confirm the rest of the suite is not a no-op.

**Still unproven, and not claimed:** everything past authentication. No credentials are
used, so `LOGIN` success, `SELECT INBOX`, a 200-message `SEARCH UNSEEN`, and a real
`FETCH` of a message body have never run against a live server. A first real run should
confirm those, and that `BODY.PEEK` leaves messages unread in the Gmail web UI.

**Also unproven on iOS.** `swift test` is the only place these run — the package is
tested on macOS and there is no iOS test action for `ThirdHandCore`, so the TLS test
proves the macOS `Network.framework` path. The framing and parser code is
platform-independent, but the socket layer is not identical across the two.

#### The Gmail API path, if it is ever worth the paperwork

Still the better long-term integration: threads rather than messages, labels, and
server-side query (`is:unread -category:promotions`) instead of a client-side filter.

**What it needs:**
- A **Google Cloud project with the Gmail API enabled**, an OAuth client of type
  "iOS", and the `gmail.readonly` scope at minimum (`gmail.modify` if Third Hand should be
  able to archive from the notification).
- **OAuth verification.** `gmail.readonly` is a *restricted* scope. Google requires a
  security assessment (CASA) before unverified users may grant it, and in testing mode
  the app is capped at **100 test users**. This is the real cost of the OAuth path —
  not the code, the paperwork.
- Endpoints: `GET /gmail/v1/users/me/threads?q=is:unread -category:promotions`, then
  `threads.get` with `format=metadata` and headers `From`, `Subject`, `Date`.
- Identity: `gmail:thread:<threadId>` — note this differs from the `gmail:message:` form
  IMAP uses, so an OAuth migration would need an id migration, not just a swap.

### Slack — good value, needs a workspace app

**Would add:** unread DMs, mentions, and anything awaiting your approval.

**What it needs:**
- A **Slack app installed to the workspace** (not a distributed app), with scopes
  `im:read`, `mpim:read`, `channels:history`, `users:read`, and a **bot user**. A
  user token would give better results (`search:read`, `dnd:read`) but Slack
  discourages distributing user-token apps.
- Auth: OAuth v2 with a PKCE mobile flow; token in Keychain.
- Endpoints: `conversations.list`, `conversations.history` with `oldest` cursor, and
  `search.messages?query=is:unread`.
- Identity: `slack:message:<channelId>:<ts>` (Slack's `ts` is the stable id;
  permalinks change with workspace renames).
- Classification: a mention containing a question → `reply`; a message in a DM where
  you are the last reader → `reply`; a message containing "approve"/"sign off" →
  `decision`.

### Docs — deliberately last

**Would add:** Google Docs/Notion documents shared with you since your last visit.
Low signal, heavy integration surface, and the `docs` source already accepts anything a
user shares. Defer past v1.2.

## What the current ceiling means for the board

The board reflects **Calendar + Reminders + unread IMAP mail + whatever the user chose
to share**. That is a smaller board than the product vision describes, and `README.md`
and the App Store description must not imply otherwise. Marketing copy that suggests
Third Hand reads your Slack — or your *read* mail, labels, or archived threads — would
be false today.

## Recommended order

1. ~~**Gmail**~~ — **done** (v1.2) over IMAP, no OAuth. The OAuth upgrade, which buys
   threads, labels and server-side queries, remains deferred behind CASA.
2. **GitHub** (v1.3) — cheapest auth, highest signal-to-effort, testable with a public
   repo and no verification process.
3. **Slack** (v1.3/1.4) — needs a workspace install, so it is per-organisation.
4. **Docs** (v1.4+) — only if users ask.
