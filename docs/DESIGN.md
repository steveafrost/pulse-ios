# Third Hand — Visual Design Specification

v1, pre-implementation. iOS 27 SDK, Swift 6, SwiftUI. Targets: `Third Hand` (iOS),
`ThirdHandWidgets`, Mac mirror `bb-plugin-pulse`. Normative: a named SwiftUI modifier or
SF Symbol is what ships, and a stated number is the value.

## 1. Principles

- **One question, one board.** *Which means:* no dashboard, no second nav root —
  detail, Settings and Capture are sheets over the board, never stack siblings.
- **Content opaque, chrome glass.** *Which means:* every row is a solid card, and
  `.glassEffect()` appears only on the filter bar, capture capsule, FAB, sheets and
  tab bar, never on text.
- **Urgency is position, not colour.** *Which means:* four section headers carry the
  message, and every tint is paired with a glyph and a word.
- **The board is quiet by default.** *Which means:* one numeric emphasis per screen
  (the Now badge); everything else is rank order, with no per-row counts or dots.
- **Every row ends in one gesture.** *Which means:* the full row opens detail, the
  trailing 44×44pt control completes it, a swipe reveals Snooze / Dismiss.
- **Nothing moves that the user did not cause.** *Which means:* three animations
  total — row→detail morph, completion collapse, section reorder — all reducible.

## 2. Colour system

Semantic tokens as `Assets.xcassets` Color Sets with Any/Dark appearances; no hex
literals in Swift, and token name = asset name.

**Text hierarchy**

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `TextPrimary` | `#1C1C1E` | `#F2F2F7` | Item title, section headers |
| `TextSecondary` | `#3C3C43` @70% | `#EBEBF5` @70% | Detail line, meta line |
| `TextTertiary` | `#3C3C43` @45% | `#EBEBF5` @45% | "seen 5h ago", section hints |
| `TextOnAccent` | `#FFFFFF` | `#FFFFFF` | Labels inside filled Now chips |

`TextPrimary`/`TextSecondary` clear **WCAG AA 4.5:1** on `SurfaceCard` in both
appearances; `TextTertiary` is metadata only, never the sole carrier of a fact, and
holds **3:1**. Both are asserted by the snapshot contrast test.

**Surfaces**

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `SurfaceCanvas` | `#F2F2F7` | `#000000` | Board scroll background |
| `SurfaceCard` | `#FFFFFF` | `#1C1C1E` | Item row card |
| `SurfaceCardPressed` | `#E5E5EA` | `#2C2C2E` | Row during touch-down |
| `Separator` | `#C6C6C8` @30% | `#38383A` | Hairline, chip borders |

**Horizon tints** — section header glyph, row leading rail, Now badge.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `HorizonNow` | `#D70015` | `#FF453A` | Now: `exclamationmark.circle.fill`, rail, FAB tint |
| `HorizonNext` | `#0A5FCF` | `#0A84FF` | Next: `arrow.right.circle.fill`, rail |
| `HorizonLater` | `#4C4C61` | `#98989F` | Later: `clock.fill`, rail |
| `HorizonFYI` | `#6E6E73` | `#8E8E93` | Nice to Know: `info.circle`, no rail |

`Horizon` owns the glyph, tint and collapse limit for each horizon; every other
table here derives from it (`.now` 3, `.next` 4, `.later` 3, `.fyi` 2). The rail is
3pt and takes `HorizonNow` only when `priority == high` **and** `due` is within 24h;
otherwise a high-priority row takes `HorizonNext`, and Later rows never take Now.

**Source identity** — glyph + label only, never on the card or rail. Light → dark:
`SourceCalendar` `#B32D0F`→`#FF9F0A` (`calendar:` · `calendar`), `SourceReminders`
`#7A3FCF`→`#BF5AF2` (`reminders:` · `checklist`), `SourceGmail` `#A8201A`→`#FF6961`
(`gmail:`, share-sheet import · `envelope`), `SourceSlack` `#5B2DA8`→`#A78BFA`
(`slack:` · `number.square` — placeholder, unused in MVP), `SourceOther`
`#56565C`→`#A1A1A6` (`github:`, `docs:`, `other:` · `link`).

Chip = `.caption2` `.medium`, foreground = source token, background = same token
@12%, `RoundedRectangle(cornerRadius: 4)`, padding H6 V2. The fill is decorative;
every token holds 4.5:1 as a label on `SurfaceCard`.

**Kind and status tints**

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `KindNeutral` | `#3C3C43` @70% | `#EBEBF5` @70% | reply, followup, review, fyi |
| `KindAttention` | `#A8500A` | `#FFD60A` | decision, rsvp, conflict — the kinds that block someone else |
| `KindDeadline` | `#B32D0F` | `#FF9F0A` | deadline |
| `StatusWaiting` | `#6E6E73` | `#98989F` | `waiting` · `hourglass` |
| `StatusSnoozed` | `#5B2DA8` | `#A78BFA` | `snoozed` · `moon.zzz.fill` + "until 4:00 PM" |
| `StatusDone` | `#2C7A3F` | `#30D158` | completion flash |
| `StatusError` | `#D70015` | `#FF453A` | error banner, denied state |

**Non-negotiable rules.** 1. Colour is never the only signal: every tint pairs with
an SF Symbol and/or a word. 2. Body text 4.5:1, glyphs and chips 3:1, both
appearances. 3. Increased Contrast (`@Environment(\.colorSchemeContrast)`): `@70%`
secondaries → 100%, `@12%` chip fills → 22%, `Separator` → 55%. 4. No token outside
these tables — new colour requires a row here first.

## 3. Typography

SF Pro Text below 20pt / display above (system default). SF Pro **Rounded** only
for the board title and the Now badge.

| Role | Style | Weight | Use |
| --- | --- | --- | --- |
| Board title | `.largeTitle` Rounded | `.bold` | "Third Hand", inline at rest |
| Section header | `.title3` | `.semibold` | "Now" + count |
| Section hint | `.footnote` | `.regular` | "High priority or due today" |
| Item title | `.headline` | `.semibold` | 2 lines |
| Item detail | `.subheadline` | `.regular` | 2 lines |
| Meta line | `.footnote` | `.regular` | source · due · people · time |
| Chip | `.caption2` | `.medium` | never wraps |
| Badge count | `.caption` Rounded | `.bold` | filter bar Now count |
| Button label | `.body` | `.semibold` | FAB, sheet primary |
| Capture capsule | `.footnote` | `.medium` | "12 items · 2m ago" |

At AX sizes: the **title**'s 2-line limit is removed at `.accessibility1`+.
**Detail** hides on the board at `.accessibility3`+ (kept in detail) so rows stay
scannable. The **meta line** never wraps — it becomes `ScrollView(.horizontal)`
with `.scrollIndicators(.hidden)` at `.accessibility2`+, one truncated line below
that. **Section hints** hide at `.accessibility1`+ (decorative). **Chips** stop
scaling at `.accessibility2`+ and drop their fill for plain `·`-separated tokens.
No fixed row height ever — `.fixedSize(horizontal: false, vertical: true)` on every
text block, because a clipped row is a bug — and
`.dynamicTypeSize(...DynamicTypeSize.accessibility5)` is the only clamp.

## 4. Spacing and layout

Base 4pt; permitted values are **4, 8, 12, 16, 20, 24, 32, 48** and no others.
Their uses: 4 = chip inner vertical padding and icon gap; 8 = chip gaps,
title→detail, card gap; 12 = detail→meta and card horizontal padding on the rail
side; 16 = card vertical padding and screen margin; 24 = section header→first row;
32 = section→section; 48 = board bottom inset above the FAB.

Screen margin 16pt horizontal, added to the safe area, never instead of it. Row
minima 72pt (title only) / 92pt (title + detail) / 112pt (+ two meta chips), all
text-driven growth, with an 8pt gap between cards that serves as the separator — no
rules. Corner radii: row 16pt, sheet content top 28pt, chips / FAB / capsule
`.capsule`, widgets 20pt; nothing is radius 0 except full-bleed dividers. Max
content width 720pt via `.frame(maxWidth: 720)` on iPad.

### 4.1 Board structure

```
┌ ScrollView (SurfaceCanvas) ────────────────┐
│ ⚠︎ Now 2        High priority or due today   │ ← sticky .bar header
│ ┌ ItemRow ───────────────────────────────┐  │   8pt gaps
│ ⌄ Show 4 more in Now                        │ ← 8pt below last row
│                                             │ ← 32pt to next section
│ → Next 4       Due tomorrow or undated      │
└─────────────────────────────────────────────┘
  [glass filter bar pinned under nav]  [glass capsule + FAB]
```

Fixed order: Now, Next, Later, Nice to Know. A zero-item section is **omitted
entirely** — headers never render empty. Before a "Show all" control appears a
section shows Now 3, Next 4, Later 3 and Nice to Know 2 rows, labelled "Show 4 more
in Now", "Show 5 more in Next", "Show 4 more in Later", "Show 6 more in Nice to
Know". The control is `.buttonStyle(.plain)`, `.footnote` `.medium`, `HorizonNext`
with a trailing `chevron.down`; expanding is inline via
`.animation(.smooth(duration: 0.25))` and relabels "Show less". Expanded state does
not persist across launches. Headers pin with `.pinnedViews([.sectionHeaders])` on
an opaque `.background(.bar)` strip — it carries a label, so glass is forbidden.

## 5. The item row

`ItemRow` is the product; everything else is scaffolding. It is one
`.accessibilityElement(children: .ignore)` button with a full-row tap target, a
separate 44pt completion control, and swipe actions on both edges.

### 5.1 Anatomy

```
┌──────────────────────────────────────────────────────────────┐
│ ▍ ★  Pick the launch date for the Payments beta        ✓  ⌄   │ 1,2,3,4,5
│ ▍    Priya needs a yes on Oct 28 or Nov 4 before she…        │ 3
│ ▍    [Slack] [Decision]  Today 5:30 PM  Priya, Marco  5h ago │ 6
└──────────────────────────────────────────────────────────────┘
```

1. **Leading rail** — `RoundedRectangle(cornerRadius: 1.5)`, 3pt, flush to the card
   edge, tinted by horizon. Absent for Nice to Know, which use plain 16pt leading
   padding (rail rows inset text 3+12pt more).
2. **Kind glyph** — 20×20pt SF Symbol `.semibold` in its kind token: reply
   `arrowshape.turn.up.left`, decision `questionmark.circle`, rsvp
   `calendar.badge.clock`, conflict `exclamationmark.triangle`, deadline
   `clock.badge.exclamationmark`, review `doc.text.magnifyingglass`, followup
   `arrow.turn.down.right`, fyi `info.circle`.
3. **Title** — `.headline` `TextPrimary`, with the **detail line** below it in
   `.subheadline` `TextSecondary` (omitted when `detail == ""`).
4. **Primary trailing affordance** — 44×44pt: `checkmark.circle` open/waiting,
   `moon.zzz.fill` snoozed, `arrow.uturn.backward.circle` waiting-on-someone;
   `TextSecondary`, becoming `StatusDone` with `.symbolEffect(.bounce, value: isDone)`.
5. **Overflow** — `ellipsis.circle` 44×44pt menu (Snooze, Dismiss, Copy quick action,
   Open link, Reopen), only when `quickActions` is non-empty, `url != nil`, or the
   item is `done`.
6. **Meta line** — `.footnote`: source chip, kind chip, `due` (`Date.FormatStyle`,
   "Today 5:30 PM"), people (first names, max two, then "+N"), `lastSeenAt`
   ("5h ago"). All but the chips are `TextTertiary`.

### 5.2 Height, truncation, newness

Padding `.padding(.horizontal, 16).padding(.vertical, 14)`, minima from 4.
Trailing affordances are **top-aligned** with the title, not centred, so they hold
their place as the row grows. Truncation: title 2 lines (∞ at AX1+) `.tail`;
detail 2 lines `.tail`, hidden at AX3+; meta line 1 line `.tail`, scrolling
horizontally at AX2+; chips never wrap (`.fixedSize()`); people cap at 2 names then
"+N".

Newness derives from `snapshot.lastViewedAt`: a row with `firstSeenAt >
lastViewedAt` gets a 6pt `Circle()` in `HorizonNext` 8pt left of the kind glyph plus
`.overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(HorizonNext.opacity(0.45), lineWidth: 1))`.
No background or weight change — weight would shift layout. Clears when that item's
detail opens, or the board is left and returned to.

### 5.3 VoiceOver contract

`.accessibilityElement(children: .ignore)` on the card, then exactly:

```
label:  "<title>. <kind spoken label>. <source spoken label>."
value:  "<detail, if any>. <due phrase>. <people phrase>. <relative time>.<status suffix>"
hint:   "Opens details"
traits: .isButton
```

due phrase `"Due today at 5:30 PM"` | `"Due Monday at 3 PM"` | `"No due date"`;
people phrase `"With Priya and Marco"` | `"With Priya and 1 other"` | `""`; relative
time `"Seen 5 hours ago"`; status suffix only when not open — `", snoozed until
4 PM"` | `", waiting on someone else"` | `", new since you last looked"`.

Kind labels: reply "Needs a reply", decision "Needs a decision", rsvp "Waiting on
your RSVP", conflict "Schedule conflict", deadline "Deadline", review "Needs
review", followup "Follow up", fyi "For your information". Source labels: "from
Calendar", "from Reminders", "from Email", "from Slack", "from a link".

`.accessibilityActions` on that same element, so the rotor exposes them: **Done**
(`store.complete(id)`), **Snooze** (opens the snooze sheet — it cannot be deferred),
**Dismiss** (`store.dismiss(id)`), **Copy action** (`quickActions.first.text`, only
when non-empty), **Open link** (`UIApplication.open`, only when `url != nil`),
**Reopen** (only when `status == done`). Reading order is one element per swipe;
section headers carry `.accessibilityAddTraits(.isHeader)` and read "Now, 2 items".

## 6. Glass usage rules

Glass is a tax on legibility; pay it only where content must show through. There
are six glass surfaces and no seventh.

### 6.1 Exhaustive allow list

| Surface | API |
| --- | --- |
| Filter bar chips | `.glassEffect(.regular, in: .capsule)` each, all in one `GlassEffectContainer` |
| Capture capsule | `.glassEffect(.regular.tint(HorizonNow.opacity(0.15)), in: .capsule)` while capturing or an error pends |
| FAB | `.glassEffect(.regular.interactive(), in: .capsule)` + `.buttonStyle(.glassProminent)` |
| Sheets, tab bar, toolbar | `.presentationBackground(.regularMaterial)`; `.tabBarMinimizeBehavior(.onScrollDown)`; `.buttonStyle(.glass)` |

### 6.2 Never glass

Item rows and cards (`.background(Color("SurfaceCard"))`), section headers (opaque
`.bar`), the board background (`SurfaceCanvas`, flat), detail body content, sheet
content areas (only the backing is material), and text of any kind — no
`.foregroundStyle(.ultraThinMaterial)` anywhere.

### 6.3 Grouping

Every glass cluster whose members sit within ~24pt of each other shares one
container with `spacing:` equal to the gap so it refracts as one body — never nest
containers; a lone element needs none. `GlassEffectContainer(spacing: 8) {
HStack(spacing: 8) { chips } }`; the capsule + FAB pair uses `spacing: 16` around a
`VStack(spacing: 16)`.

### 6.4 `glassEffectID` — used in exactly one place

The row→detail morph, on the detail header capsule only:
`ItemRow(item).glassEffectID(item.id, in: boardNamespace)` on the board and
`DetailHeader(item).glassEffectID(item.id, in: boardNamespace)` in the sheet, with
the namespace declared on `BoardView` and injected into the sheet. The morphing
element is deliberately the header capsule, not the row card — a morphing card
would have to be glass, which 6.2 forbids. Row content cross-fades, never morphs.

### 6.5 Reduce Transparency

`@Environment(\.accessibilityReduceTransparency)`; one `GlassStyle` modifier
substitutes everywhere. Filter chip → `.background(.regularMaterial, in: .capsule)`
plus `.strokeBorder(.separator)`. Capture capsule → the same background, no border.
FAB → the same background plus `.buttonStyle(.borderedProminent)`, keeping
`.tint(HorizonNow)`. Sheet → `.presentationBackground(.regularMaterial)`, unchanged.
No code path calls `.glassEffect()` without consulting this value.

## 7. Motion

Three animations ship; no others.

### 7.1 Row → detail

`.snappy(duration: 0.38, extraBounce: 0.02)` through `glassEffectID` (6.4). The row's
content fades 1→0.35 over 0.18s, no scale, as the sheet covers it. Sheet:
`.presentationDetents([.large])`, `.presentationDragIndicator(.visible)`,
`.presentationCornerRadius(28)`. Dismiss reverses at `.snappy(duration: 0.3)` with
content opacity restored over 0.15s.

### 7.2 Completion — the one that matters

From the row control, a VoiceOver action, or a mirror command landing:

1. `0ms` — glyph → `checkmark.circle.fill` in `StatusDone`, `.symbolEffect(.bounce, options: .speed(1.4))`.
2. `0ms` — card background flashes to `StatusDone.opacity(0.12)` and back over 320ms `.easeOut`.
3. `120ms` — the card collapses via `.scaleEffect(y: 0.01, anchor: .top)` + `.opacity(0)`, 240ms `.smooth(duration: 0.24)`. Only the removed card animates; neighbours never fade individually.
4. `120ms` — the list closes the gap as one unit with `.spring(response: 0.42, dampingFraction: 0.86)` on the enclosing `LazyVStack` (animate the binding, not the rows).
5. Counts use `.contentTransition(.numericText())`. An emptied section collapses its header on the step-3 curve and the next section slides up in the same spring; a fully empty board cross-fades to "All clear" over 300ms `.easeInOut`.

The card stays in the hierarchy until step 3 finishes so the flash is visible —
a two-phase state (`marking → removing`) inside `ItemRow`.

### 7.3 Section reorder

On a horizon change from a capture pass the row leaves on the step-3 curve and
arrives in the destination at `.smooth(duration: 0.28)` after a 60ms delay; both
counts use `.contentTransition(.numericText())`.

### 7.4 Reduce Motion

`@Environment(\.accessibilityReduceMotion)`. When true, 7.1 loses the matched
geometry for a standard sheet present with a 0.2s opacity cross-fade; 7.2 keeps
steps 1–2 (state feedback, not travel), makes step 3 an instant removal and step 4
a jump, and cross-fades step 5 over 0.2s; 7.3 is instant with no delay; and
`.symbolEffect(.bounce)` is dropped. Haptics are not motion, so they survive:
`.sensoryFeedback(.success, trigger: completedCount)` on completion and
`.sensoryFeedback(.impact(weight: .light), trigger: snoozeCount)` on snooze.

## 8. Screen inventory

### 8.1 Board (`BoardView`) — the app

Layout as 4.1. Nav bar carries an inline `.largeTitle` "Third Hand" plus two glass
toolbar buttons (`gearshape`, `ellipsis`). The filter bar is one horizontally
scrolling `ScrollView` of chips — "All 11", then one per source present in the
order Calendar / Reminders / Email / Slack / Docs; selecting one filters the board
and persists in `@AppStorage("boardFilter")`, and "All" carries the Now count as a
`Text` badge in `HorizonNow`.

States: **loading** — four 24pt header and three 92pt card placeholders in
`SurfaceCard` @0.5, `.redacted(reason: .placeholder)`, no spinner; **clear** 9.1;
**never captured** 9.2; **denied** 9.3; **populated** as described; **error with
cache** — items render normally and the capture capsule becomes
`exclamationmark.arrow.trianglehead.2.clockwise.rotate.90` + "Couldn't refresh ·
Try again" in `StatusError`, tap forcing a capture, because an error never blocks
the board. Primary action: the FAB, resolving the topmost open Now item with
`checkmark` + "Done", plus that item's title above the glyph at `.accessibility1`+.

### 8.2 Item detail (`ItemDetailView`, sheet)

```
┌───────────────────────────────────────┐
│ ⚠︎ Decision · Calendar · with Priya    │ glass header capsule (morphs from row)
│ Pick the launch date for the Payments │ .title2 .semibold, opaque card
│ beta                                  │
│ Priya needs a yes on Oct 28 or Nov 4  │ .body
│ before she books the customer webinar.│
│ Due    Today, 5:30 PM                 │ KeyValue rows, opaque
│ People Priya Raman, Marco Alves       │
│ Source Calendar · opens in app ↗      │
│ QUICK ACTIONS  [ Yes to Oct 28 ⧉ ]    │ copy / open buttons, .bordered
│ HISTORY        · Created 9:02 AM      │
├───────────────────────────────────────┤
│ ( Snooze )  ( Dismiss )  ( Done )     │ glass action bar, glassProminent primary
└───────────────────────────────────────┘
```

**Quick action labels.** `QuickAction.label` is the button title and is written in
the imperative ("Open thread", "Accept", "Yes to Oct 28"), never as a noun naming
the payload. The row renders it verbatim and adds only a behaviour glyph
(`doc.on.doc` for a copy action, `arrow.up.right.square` for one that opens a URL,
`ellipsis.circle` for a menu when the action carries both); it never prefixes the
label with a verb or wraps it in quotes, because "open the thing called *Open
thread*" renders as "Open “Open thread”" and reads to VoiceOver as left-quote. A
quick action whose URL equals the item's own `url` replaces the standalone "Open
link" button rather than duplicating it.

States: **waiting** — banner "Waiting on Marco since Oct 20" in `StatusWaiting`;
**done** — card at 60% opacity with a "Done · Reopen" banner; **mirror pending** —
footnote "Action sent to Mac" while a command is unacked; **error** — `alert`
"Couldn't save that. Try again.". Primary action: Done.

### 8.3 Secondary sheets

| Sheet | Content | States | Primary action |
| --- | --- | --- | --- |
| `SettingsView` (`.large`) | Sources (Calendar / Reminders toggles + last sync), Freshness (last capture, "Refresh now"), Appearance (`@AppStorage("density")`: Comfortable = 16pt, Compact = 8pt with detail hidden), Privacy ("Data stays on device"), About | granted / denied per source + "Open Settings" deep link | **none** — configuration never carries `glassProminent` |
| `PermissionPrimerView` (full-screen cover) | `calendar.badge.checkmark` (64pt, `HorizonNext`), "Third Hand reads your calendar and reminders to know what needs you.", bullets "Nothing leaves your device" / "No account" / "You can revoke any time", `Continue` (`glassProminent`), `Not now` (`.plain`, `TextSecondary`) | single | `Continue` raises the system prompt; Not now dismisses to 9.2 |
| `SnoozeSheet` (`.height(320)`) | Later today (5 PM), Tonight (8 PM), Tomorrow 9 AM, This weekend (Sat 9 AM), Pick a time… (`DatePicker` `.wheel`) | single | none — the options are the action; a tap snoozes and dismisses |

## 9. Empty states

Real product copy; use exactly these words. All three share one template: 64pt
glyph, `.title2` `.semibold` heading, `.body` `TextSecondary` centred at max width
320pt, buttons, then a `.footnote` `TextTertiary` line.

| State | Glyph · tint | Heading | Body | Buttons · footnote |
| --- | --- | --- | --- | --- |
| **9.1 Genuinely clear** (captured before, nothing needs the user) | `checkmark.circle.fill` · `StatusDone` | "You're all clear" | "Nothing needs you right now. Third Hand is watching your calendar and reminders, and you can share a Slack thread, a pull request, or an email here to add it." | `Refresh` (`.bordered`, not prominent) · "Last checked 2 minutes ago" |
| **9.2 Never captured** (no sources connected) | `sparkles` · `HorizonNow` | "Let's see what needs you" | "Connect your calendar and reminders. Third Hand reads them on this device and never sends anything anywhere." | `Connect Calendar` (`glassProminent`), `Not now` (`.plain`) · "You can turn sources on or off later in Settings." If only Reminders is available the primary becomes `Connect Reminders`. |
| **9.3 Permission denied** | `calendar.badge.exclamationmark` · `StatusError` | "Third Hand can't see your calendar" (the paused source's name: "Third Hand can't see your reminders") | "Calendar access is off. Turn it on in Settings and Third Hand will fill this board." | `Open Settings` (`.bordered`), `Choose sources` (`.plain`) · "Third Hand reads on this device. Nothing leaves it." If reminders still work, those items render above this as a non-blocking banner instead of a full-screen state. |

9.3 applies only when the board is **empty** because of the denial
(`BoardState.EmptyReason.denied`). With any item renderable the denial is the
non-blocking `SourceBanner` above, and the identical sentence appears there with
the same "Open Settings" button — one wording, two placements.

**9.4 Section-empty rule.** A zero-item section is never rendered (4.1); "Nothing
in Next" is never written.

## 10. Accessibility checklist

Each line is a pass/fail gate in `ThirdHandTests/AccessibilityTests.swift` or a
screenshot in 12. All twelve must pass before App Store submission.

- [ ] **AX5:** no row clips; title fully visible; detail hidden at AX3+; meta scrolls horizontally; FAB label wraps; sheets scroll with the action bar pinned above the keyboard.
- [ ] **VoiceOver order:** title → filter bar → header ("Now, 2 items", header trait) → one element per row → show-all → next section, nothing twice.
- [ ] **VoiceOver actions:** rotor exposes Done, Snooze, Dismiss and conditionally Copy action / Open link / Reopen; each completes in place and announces ("Done. 3 items left in Now.").
- [ ] **Hit targets** ≥44×44pt: row checkmark, overflow, filter chips, FAB, swipe actions, show-all row. **Reduce Motion** per 7.4; **Reduce Transparency** per 6.5, with nothing illegible.
- [ ] **Bold Text:** `.regular` weights in 3 resolve to `.semibold` with no reflow.
- [ ] **Increased Contrast** per section 2, rule 3.
- [ ] **Differentiate Without Colour:** headers and chips carry glyph + word, snoozed carries glyph + "until", newness carries a dot + the VoiceOver suffix.
- [ ] **Switch Control:** every action is in the tree, FAB first after the filter bar.
- [ ] **Contrast:** snapshot test asserts 4.5:1 for `TextPrimary`/`TextSecondary` over `SurfaceCard` and `SurfaceCanvas`, both appearances.
- [ ] **Landscape / iPad:** board capped at 720pt; no title exceeds 3 lines.

## 11. Widgets and Live Activity

**Widgets.** `.systemSmall` (Third Hand Now) shows the Now count in Rounded `.title`, the
top item title over 2 lines and its source glyph. `.systemMedium` shows Now (≤2)
and Next (≤2), title only, with a leading horizon glyph; a row tap deep-links
`thirdhand://item/<id>`. `.systemLarge` shows all four headers with ≤3 rows each (title +
due) and never scrolls or shows all.

**Lock Screen.** `.accessoryRectangular` = Now count plus the first item title on 2
lines. `.accessoryInline` = "Third Hand · 2 need you". `.accessoryCircular` = a `Gauge`
of the Now count (0–9, `.accessoryCircularCapacity`) with the count centred.

**Live Activity.** Meeting title, countdown ("in 12 min"), short location — with the
calendar glyph in `.compactLeading`, the countdown in `.compactTrailing`, and
`.minimal` as the glyph only.

Lock Screen rules: monochrome only (the system desaturates — never bake in colour),
all content `.widgetAccentable`, no chips, no fills, at most one glyph, ~30
characters of title before truncation, `Gauge` for numbers rather than a coloured
dot. Every widget background is `.containerBackground(for: .widget) {
Color("SurfaceCard") }` and nothing else; widgets never use material or glass.

## 12. Screenshot checklist (App Store Connect)

| # | Device · size | Must show |
| --- | --- | --- |
| 1 | 6.9" 1320×2868 | Board populated, Now expanded to 3 rows, "All 11" filter bar, FAB; no sheet, no keyboard |
| 2 | 6.9" | Detail sheet over the board: header capsule, quick actions, action bar |
| 3 | 6.9" | Completion moment — row mid-collapse, `StatusDone` flash, count animating (still at 140ms) |
| 4 | 6.9" | "You're all clear" (9.1) with "Last checked 2 minutes ago" |
| 5 | 6.1" 1179×2556 | Board at default Dynamic Type, all four sections visible |
| 6 | 6.1" | Board at **AX3** — wrapped title, hidden detail, horizontal meta |
| 7 | 13" 2064×2752 | Board centred at 720pt with canvas margins; detail sheet at `.large` |
| 8 | 13" | Home Screen with the small, medium and large Third Hand widgets |
| 9 | 6.9" Lock Screen | All three Lock Screen widgets + Live Activity, expanded Dynamic Island |
| 10–11 | 6.9" | Dark appearance of #1 (the tokens differ), then #1 with **Reduce Transparency on** to prove the material fallback |

Devices: #1–#4 and #9–#11 on iPhone 17 Pro Max, #5–#6 on iPhone 17 Pro, #7–#8 on
iPad Pro 13".

Real data only, no lorem ipsum; status bar overridden to 9:41 with full battery and
Wi-Fi; default text size except #6. The plugin mirror is never submitted — there is
no Mac Catalyst target.
