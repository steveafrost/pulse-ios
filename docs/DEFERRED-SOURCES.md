# Deferred capture sources

Why Pulse captures less than it declares, and what it would take to capture the rest.

## The current, honest position

`Source` declares six values (`PulseCore/Sources/PulseCore/Models/Enums.swift:16`):
`slack`, `gmail`, `calendar`, `github`, `docs`, `other`.

Of those, **only `calendar` and `reminders` pull data autonomously**. For Slack,
Gmail, GitHub and Docs, Pulse has **no OAuth application registered and no way to
authenticate**. A source that tried to call those APIs today would fail to
authenticate and return nothing — and a source that quietly returns nothing makes the
board *look* complete while being blind, which is worse than an absent source.

So instead of shipping three clients that cannot work, M7.1 shipped:

**`SharedLinkSource`** — the user shares a Slack thread, a GitHub PR or a Gmail
message into Pulse via the `PulseShare` app extension, and it becomes an item. This is
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
even when Pulse cannot tell what it wants. An unknown host becomes `fyi` — information,
not a task.

**Its ceiling is exactly what the user shared.** It cannot see an unshared Slack
mention, an unread Gmail thread, or a PR awaiting your review.

## What each deferred source would add

### GitHub — the highest value per unit of work

**Would add:** PRs where your review is requested, issues assigned to you, your own PRs
with failing checks or unaddressed review comments, and mentions.

**Why it is the best first integration:** PR review requests are exactly the shape Pulse
is built for — a `review` kind with a real deadline, real participants, and an obvious
done action. GitHub also has the most pleasant auth story for a personal app.

**What it needs:**
- A **GitHub App** (preferred over OAuth App: finer scopes, installable, no user token
  to store). Minimum scopes: `pull_requests:read`, `issues:read`, plus the
  `checks:read` permission for CI state.
- Auth flow: device flow is acceptable for v1.1 and avoids a redirect URI entirely,
  which matters because Pulse has no server.
- Token storage: **Keychain**, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — never
  UserDefaults, never the app group (the widget does not need it).
- Poll interval: 5–15 min behind `BGAppRefreshTask`, with ETag/conditional requests so
  a quiet poll costs almost nothing.
- Endpoints: `GET /issues?filter=assigned`, `GET /pulls?state=open` +
  `review-requested:@me` search, `GET /repos/{o}/{r}/pulls/{n}/reviews`.
- Identity: `github:pr:<owner>/<repo>#<n>` and `github:issue:<owner>/<repo>#<n>`, following
  `ItemIdentity`'s existing template, and stable across title edits.

### Gmail — highest value, worst auth

**Would add:** threads awaiting your reply, messages from people you cannot ignore, and
anything flagged. This is where the "what needs me" question most literally lives.

**What it needs:**
- A **Google Cloud project with the Gmail API enabled**, an OAuth client of type
  "iOS", and the `gmail.readonly` scope at minimum (`gmail.modify` if Pulse should be
  able to archive from the notification).
- **OAuth verification.** `gmail.readonly` is a *restricted* scope. Google requires a
  security assessment (CASA) before unverified users may grant it, and in testing mode
  the app is capped at **100 test users**. This is the real reason Gmail is deferred —
  not the code, the paperwork.
- Endpoints: `GET /gmail/v1/users/me/threads?q=is:unread -category:promotions`, then
  `threads.get` with `format=metadata` and headers `From`, `Subject`, `Date`.
- Identity: `gmail:thread:<threadId>`.
- Classification: a thread where you are the last recipient and nobody has replied →
  `reply`; a thread containing a question directed at you → `reply` high.

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

## What the SharedLink ceiling means for the board

Until at least GitHub lands, the board reflects **Calendar + Reminders + whatever the
user chose to share**. That is a smaller board than the product vision describes, and
`README.md` and the App Store description must not imply otherwise. Marketing copy that
suggests Pulse reads your Slack or Gmail would be false today.

## Recommended order

1. **GitHub** (v1.1) — cheapest auth, highest signal-to-effort, testable with a public
   repo and no verification process.
2. **Gmail** (v1.2) — highest value, but start the CASA security assessment early; it is
   the long pole and it is not engineering.
3. **Slack** (v1.2/1.3) — needs a workspace install, so it is per-organisation.
4. **Docs** (v1.3+) — only if users ask.
