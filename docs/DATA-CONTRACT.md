# Third Hand Data Contract — v1

The single source of truth for item shape and sync. Both the iOS app and the
`bb-plugin-thirdhand` mirror implement this. Change it here first, then in both
implementations, then bump `schemaVersion`.

## Roles

| Component | Role |
| --- | --- |
| `ThirdHandApp` (iOS) | **Owner.** Reads sources, applies capture rules, owns user actions. |
| `bb-plugin-thirdhand` (Mac) | **Mirror.** Reads the snapshot, renders it, forwards user actions. |
| iCloud Drive ubiquity container | Transport. UTF-8 JSON files. |

The plugin may never author items. Its Done/Snooze/Dismiss writes go back to
iOS through a command file; iOS applies them and republishes the snapshot.

## Transport layout

Inside the app's iCloud container (`iCloud.com.steveafrost.thirdhand`), under
`Documents/ThirdHand/`:

```
snapshot.json      iOS -> plugin. Full item set. Written atomically (tmp + rename).
commands.jsonl     plugin -> iOS. One JSON action per line. Append-only.
commands.ack.jsonl iOS -> plugin. Ids of commands consumed. Append-only.
```

`THIRDHAND_HOME` env var overrides the Mac-side directory so the plugin can be
pointed at any mirrored folder (used by tests and by users without iCloud).

### Write protocol

1. iOS serialises the whole item set and writes `snapshot.json` via
   `write(tmp) -> rename(snapshot.json)`. Readers never see a partial file.
2. Plugin polls `snapshot.json` (default 5 s, and on FSEvents change) and
   reloads when `generatedAt` advances.
3. Plugin appends to `commands.jsonl`:
   `{"id":"<uuid>","at":"<ISO>","op":"done|dismiss|snooze|reopen","itemId":"...","until":"<ISO|null>","reason":"<string|null>"}`
4. iOS reads `commands.jsonl` on foreground, on background fetch, and every
   15 s while active; applies each unacked `id`; appends `{"id":...}` to
   `commands.ack.jsonl`; rewrites `snapshot.json`.
5. Plugin drops acked command ids from its local pending queue.

Conflict rule: **iOS wins on item content.** The plugin only ever asserts
transitions (done/snooze/dismiss/reopen). A plugin command is applied only if
its `at` is newer than the item's `updatedAt`. Otherwise dropped with a log line.

## Snapshot envelope

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-23T18:04:11.000Z",
  "deviceName": "Steve's iPhone",
  "lastViewedAt": "2026-10-23T17:40:00.000Z",
  "items": [],
  "runs": [],
  "draft": null
}
```

`items` carries **every** item, including `done` and `dismissed` closed within
the last 3 days. Older closed items are pruned on write. The plugin filters for
display.

## ThirdHandItem (field-for-field identical to plugin `types.ts`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `string` | `"<source>:<stable id>"`. Source prefix must match a known source. Immutable. |
| `source` | `slack\|gmail\|calendar\|github\|docs\|other` | Derived from the `id` prefix on creation. |
| `kind` | `reply\|decision\|rsvp\|conflict\|deadline\|review\|followup\|fyi` | Capture rule's classification. |
| `title` | `string` | Non-empty. One line. |
| `detail` | `string` | May be `""`. Multi-line allowed. |
| `url` | `string \| null` | `https://` only when present. |
| `due` | `string \| null` | ISO 8601. |
| `priority` | `high\|normal\|low` | |
| `people` | `string[]` | Display names. |
| `status` | `open\|waiting\|snoozed\|resolved\|done\|dismissed` | See state machine. |
| `snoozedUntil` | `string \| null` | Set only while `snoozed`. |
| `resolution` | `string \| null` | Free-text reason on close. |
| `firstSeenAt` | `string` | ISO. Set once. |
| `lastSeenAt` | `string` | Updated by every capture pass that still finds the item. |
| `updatedAt` | `string` | Any mutation. |
| `resolvedAt` | `string \| null` | |
| `lastChangedBy` | `string` | `"user"`, `"capture"`, `"mirror"`. |
| `history` | `HistoryEntry[]` | Capped at 50, oldest dropped. |
| `quickActions` | `QuickAction[]` | Max 3. |
| `agentSkills` | `string[]?` | Plugin-computed; iOS writes `[]`. |
| `action` | `ItemAction \| null` | Plugin-side agent thread. iOS round-trips unchanged. |

`HistoryEntry`: `{ at, by, change, reason?, until? }`
`QuickAction`: `{ label (1-32 chars), text? (<=1500 chars), url? (https) }` - at least one of `text`/`url`.
`ItemAction`: `{ threadId, status: running|ready|failed, startedAt, finishedAt|null, summary|null, seenAt|null }`

## State machine

```
                 capture: status open|waiting|resolved
                        │
   ┌────────────────────┴────────────────────┐
   │                                         │
 open ⇄ waiting ──user snooze──► snoozed ──expiry──► open
   │                                │
   │ user done/dismiss              │ user done/dismiss
   ▼                                ▼
 done / dismissed ──user reopen──► open
```

Rules (must match `lib/store.mjs`):

- `done` and `dismissed` are **sticky**. A capture pass updates descriptive
  fields (`title`, `detail`, `url`, `due`, `people`, `quickActions`) but leaves
  the status alone.
- A capture pass may reopen a sticky item **only** with an explicit
  `reopen: true` and a non-empty `reason`. That reason goes into `history`.
- `snoozed` is sticky until `snoozedUntil`; an expired snooze reads back as
  `open` (`effectiveStatus`) and is normalised on the next capture pass.
- Single active `action` per item. Starting one while another runs is refused.

## Capture identity

| Source | Id template |
| --- | --- |
| calendar | `calendar:event:<ekEvent.eventIdentifier>` |
| calendar conflict | `calendar:conflict:<YYYYMMDD>:<8-char hash of sorted participant set>` |
| reminders | `reminders:reminder:<calendarItemIdentifier>` |
| mail (share sheet) | `gmail:message:<rfc822 Message-ID>` |

An item becomes `resolved` (not `done`) when a later pass no longer detects it.
`resolved` is non-sticky and can return to `open` if detected again. Only user
actions are terminal, and only user actions set `done`/`dismissed`.

## Classification rules (MVP, on-device only)

| Detector | kind | priority | notes |
| --- | --- | --- | --- |
| Meeting accepted=false, start within 7d | `rsvp` | high if <24h else normal | people = organizer + attendees |
| Two accepted events overlap > 5 min, today or tomorrow | `conflict` | high | one item per pair per day |
| Event start within 60 min, not all-day | `deadline` | high | title = event title |
| Reminder overdue or due today, incomplete | `deadline` | high if overdue | |
| Event/reminder with a link in notes and no action needed | `fyi` | low | collapsed under Nice to Know |
| Imported mail awaiting a reply | `reply` | normal | share-sheet import path |

`fyi` is informational; the UI groups it under **Nice to Know** and does not
count it in the Now badge.

## Versioning

`schemaVersion` is an integer. A reader seeing a higher version than it supports
must refuse to write and surface an "update Third Hand" state rather than silently
dropping fields. Adding an optional field does not bump the version; removing or
retyping a field does.
