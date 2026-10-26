# Pulse — Visual Design Specification

v1, pre-implementation. iOS 27 SDK, Swift 6, SwiftUI. Targets: `Pulse` (iOS),
`ThirdHandWidgets`, Mac mirror `bb-plugin-thirdhand`. Normative: a named SwiftUI modifier or
SF Symbol is what ships, and a stated number is the value.

## 1. Principles

- **One question, one board.** *Which means:* no dashboard, no second nav root —
  detail, Settings and Capture are sheets over the board, never stack siblings.
- **Content opaque, chrome glass.** *Which means:* every row is a solid card, and
  `.glassEffect()` appears only on the filter bar, capture capsule, FAB, sheets and
  tab bar, never on text.
- **Urgency is position, not colour.** *Which means:* four section headers carry the
  message, and every tint is paired with a glyph and a word. **Enforced, not just
  stated:** the row rail, the section counts and the filter bar's selected chip each
  used to spend a saturated tint on things that are not urgent. All three now reserve
  colour for the rows and states that earn it (see §2.1).
- **The board is quiet by default.** *Which means:* one numeric emphasis per screen
  (the Now badge); everything else is rank order, with no per-row counts or dots.
  **Enforced:** a row used to show its kind three times inside 20pt — glyph, glyph
  tint, and a redundant kind chip. The chip is gone (§5.1).
- **Nothing moves that the user did not cause.** *Which means:* three animations
  total — row→detail morph, completion collapse, section reorder — all reducible.
  The craft pass adds exactly one more, the §7.2b board load-in, which is `onAppear`
  choreography rather than a response to a gesture, and which shows its **final
  state instantly** under Reduce Motion.
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
3pt and takes `HorizonNow` only when `priority == high` **and** `due` is within 24h
(overdue counts — an overdue high-priority item is more urgent than one due in an
hour, so there is deliberately no lower bound); it is then 4pt. Otherwise a
high-priority row takes `HorizonNext`, and the ordinary case takes the neutral
`RailNeutral` token below. Later rows never take Now.

### 2.1 Where colour is allowed to be loud

The craft pass rationed saturation. Before it, a single board screenshot carried
red on the row rails, the Now count, the "All" filter chip, every Deadline chip and
the FAB — five red objects competing, which is the same as none of them mattering.

| Element | Before | After |
| --- | --- | --- |
| Row rail | `horizon.tint` on every rail row | `RailNeutral`; `HorizonNow` only when urgent |
| Section count | horizon tint on all four | tint **only** on Now; tertiary elsewhere |
| Filter bar selected chip | `.tintedUrgent` (red) | `.selected` (foreground tint) |
| Kind glyph | always its kind tint | attention tint only for blocking kinds; tertiary otherwise |
| Kind chip | shown beside the glyph | **removed** |
| FAB | `HorizonNow` | `HorizonNow` — unchanged, and now the only large red object |
| Now badge | `HorizonNow` | unchanged — §1's one numeric emphasis |

The rule this encodes: **red on the board means "this one, now"**, and nothing
else may use it. Adding `.selected` to `ThirdHandGlassVariant` was the enabling
change, so a selected chip no longer has to borrow the urgent tint to look chosen.

`RailNeutral` (new token) is `#D1D1D6` light, `#3C3C3C` dark, `#8E8E8E` increased
contrast — a structural grey that reads as a spine, not an alarm.

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

**Two faces, one job each.** **New York** (`design: .serif`) names the board — the
board title, the horizon headings, and empty-state headings. **SF Pro** does
everything that is read as data: titles, detail, meta, chips, counts, labels.

Why a serif at all: it is what makes the board read as a considered personal
*ledger* rather than a default SwiftUI list, and it is the single cheapest way to
avoid the anonymous look. Why only there: a serif row title measurably slows the
scan the board exists for, and a serif footnote is muddy at 13pt. Serif is a
*voice*, so it is spent on two lines and nowhere else.

Why New York and not a bundled face: it ships with iOS, so there is no file to
license, no binary to verify, no `UIAppFonts` entry, and no risk of shipping a
font that fails to load. Because it is reached through a **text style** rather than
a point size, it scales through Dynamic Type and reflows at AX5 exactly as SF does
— which a `Font.custom(_:size:)` with a fixed size would not.

SF Pro **Rounded** remains only on the Now badge.

| Role | Style | Weight | Use |
| --- | --- | --- | --- |
| Board title | `.largeTitle` **Serif** | `.bold` | "Pulse", inline at rest |
| Section header | `.title3` **Serif** | `.semibold` | "Now" + count |
| Section hint | `.footnote` | `.regular` | "High priority or due today" |
| Item title | `.headline` | `.semibold` | 2 lines |
| Item detail | `.subheadline` | `.regular` | 2 lines |
| Meta line | `.footnote` | `.regular` | source · due · people · time |
| Chip | `.caption2` | `.medium` | never wraps |
| Badge count | `.caption` Rounded | `.bold` | filter bar Now count |
| Button label | `.body` | `.semibold` | FAB, sheet primary |
| Capture capsule | `.footnote` | `.medium` | "12 items · 2m ago" |
| Empty heading | `.title2` **Serif** | `.semibold` | "You're all clear" |
| Key/value label | `.subheadline` | `.semibold` | Settings rows, account facts |

**Tracking.** `ThirdHandTracking.eyebrow` (0.8) on uppercase group labels only, and
`ThirdHandTracking.count` (0.5) on the horizon count. Letterspacing is used in
exactly those two places: it is a way to buy distinctiveness without a bundled
face, but applying it to a sentence that is actually read damages legibility. The
serif headings use `-0.2` tracking, because a high-contrast serif set at display
size opens up too much at default tracking.

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
│ ▍    [Slack]            Today 5:30 PM  Priya, Marco  5h ago │ 6
└──────────────────────────────────────────────────────────────┘
```

**One chip, not two.** The craft pass removed the kind chip. It restated the kind
glyph (2pt to its left) and the VoiceOver label, so a row asserted its kind three
times inside 20pt. The **source** chip stays because source is the one fact the eye
cannot get any other way — the glyph encodes kind, not source. Nothing is lost for
VoiceOver: the kind is still in the row's accessibility label.

1. **Leading rail** — `RoundedRectangle(cornerRadius: 1.5)`, flush to the card
   edge. **3pt neutral (`RailNeutral`) at rest; 4pt `HorizonNow` only when the row
   is genuinely urgent** (high priority and due within 24h, overdue included).
   Absent for Nice to Know, which use plain 16pt leading padding (rail rows inset
   text 3+12pt more).

   This is the change that did the most for the board. The rail used to take
   `horizon.tint`, so *every* Now row carried a saturated red spine and the board
   read as a wall of alarms — which §1's "urgency is position, not colour" already
   forbade. A neutral rail keeps the structural cue (this card has a horizon) and
   leaves the red to the one row that earns it. A high-priority row further out
   keeps `HorizonNext`.

2. **Kind glyph** — 20×20pt SF Symbol `.regular` (was `.semibold`), in its kind
   token only for the kinds that block another person — `decision`, `rsvp`,
   `conflict`, `deadline`. The rest (`reply`, `review`, `followup`, `fyi`) drop to
   `TextTertiary`: the *shape* still identifies the kind, but it stops competing
   with the title. Glyphs: reply
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

Padding `.padding(.horizontal, 16).padding(.vertical, 12)`, minima from 4.

**The minima were not the problem.** They were 72/92/112 and are now 56/76/92 — but
measuring the shipped board showed the minima were never the binding constraint:
rows stood at ~115pt because the *detail* wrapped to two lines, not because a floor
held them up. Tightening the floor alone would have changed nothing on screen. The
real height came from three things, and each is now addressed:

1. `vertical` padding 14 → 12 (§4's own 12pt step, not an off-scale 14).
2. The **second meta chip was removed** (see 5.1) — one pill instead of two.
3. The minima dropped to the floor the content actually needs.

Minima remain a floor, never a cap: nothing here truncates a row, and every text
block still carries `.fixedSize(horizontal: false, vertical: true)`.
Trailing affordances are **top-aligned** with the title, not centred, so they hold
their place as the row grows. Truncation: title 2 lines (∞ at AX1+) `.tail`;
detail 2 lines `.tail`, hidden at AX3+; meta line 1 line `.tail`, scrolling
horizontally at AX2+; chips never wrap (`.fixedSize()`); people cap at 2 names then
"+N".

Newness derives from `snapshot.lastViewedAt`: a row with `firstSeenAt >
lastViewedAt` gets a 6pt `Circle()` in `HorizonNext` 8pt left of the kind glyph plus
`.overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(HorizonNext.opacity(0.35), lineWidth: 1))`.
The border dropped from 0.45 to 0.35 so it reads as a hint rather than a fourth
competing signal.
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

### 7.2b Board load-in — the signature moment

The board's one piece of choreography. On first appearance each row fades up from
`opacity 0` and rises 10pt, over `.easeOut(duration: 0.34)`, each row starting 32ms
after the one above it, **capped at 240ms total** so a long board does not spend a
second and a half arriving. The stagger index runs across the whole board rather
than restarting per section (`BoardView.loadInOffset(forSection:)`), so Now 1–5 are
rows 0–4 and Next begins at 5 — including when a section is expanded.

Deliberately a breath, not a performance: 10pt and 0.34s, because this is a board a
busy person opens a hundred times a day and anything larger reads as decoration.

**Reduce Motion shows the final state immediately.** `LoadIn.body` returns the
content untouched when `motion.reduceMotion` is true — no transition, no delay, no
opacity change. This is not a shortened animation; there is no window in which a
row is half-arrived.

### 7.3 Section reorder

On a horizon change from a capture pass the row leaves on the step-3 curve and
arrives in the destination at `.smooth(duration: 0.28)` after a 60ms delay; both
counts use `.contentTransition(.numericText())`.

### 7.4 Reduce Motion (unchanged, and now also covers 7.2b)

`@Environment(\.accessibilityReduceMotion)`. When true, 7.1 loses the matched
geometry for a standard sheet present with a 0.2s opacity cross-fade; 7.2 keeps
steps 1–2 (state feedback, not travel), makes step 3 an instant removal and step 4
a jump, and cross-fades step 5 over 0.2s; 7.3 is instant with no delay; and
`.symbolEffect(.bounce)` is dropped. Haptics are not motion, so they survive:
`.sensoryFeedback(.success, trigger: completedCount)` on completion and
`.sensoryFeedback(.impact(weight: .light), trigger: snoozeCount)` on snooze.

## 8. Screen inventory

### 8.1 Board (`BoardView`) — the app

Layout as 4.1. Nav bar carries an inline `.largeTitle` "Pulse" plus two glass
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
| `SettingsView` (`.large`) | **What Pulse can see** (one row per source: glyph, name, state), **Email** (one row → `EmailAccountView`), **Privacy** ("Everything stays on this device."), **About** (version/build) | granted / denied per source + "Open Settings" deep link | **none** — configuration never carries `glassProminent` |
| `EmailAccountView` (`.large`) | See §8.4 | not connected / connected / password needed | `Connect` · `Save password` (`glassProminent`) |

**What changed and why.** `SettingsView` has been specified here since v1 and did
not exist in the codebase — `onOpenSettings` deep-linked straight out to iOS
Settings, so the app could say "Calendar is off" and offer nothing about it. It is
now a real screen with the only thing it needs: a per-source truth table with the
fix beside each degraded source.

**It was still unreachable, which is what broke email.** The screen was built but
only ever constructed inside the DEBUG `DemoRoot`, so in a Release build there was
no way to open it: the board's toolbar had only the "Recently closed" button, and
every "Open Settings" on the board went to *iOS* Settings. A user told to connect
a mailbox could walk the entire app and never find the form — the mailbox screen
existed and nothing could present it. The board now carries a gear (top-leading)
when the build has a mailbox, and a paused *mailbox* routes its button to
`EmailAccountView` rather than to iOS Settings, which has no mail row to turn on.
Two smaller defects fell out of the same path: `onOpenEmail` was `{}`, so the
Settings → Mailbox row was inert; and `EmailAccountModel.status` was set only in
`init`, so a mailbox that had just signed in still read "Not connected". A capture
pass now feeds its result back through `EmailAccountModel.apply(_:)`.

Three rows were **deliberately not built**, because they would each be a lie:

- *Appearance / density.* The app follows the system. A density switch that only
  changed padding would be a setting with no job.
- *Notification toggles.* The board is the notification; there are no pushes.
- *Accounts / sign-in.* There is no server and no account (§10).

Each source row carries its **own label and glyph** rather than reading
`Source.title`. That is not cosmetic: reminders and shared links both travel on the
wire as `.other` (the contract reserves no case for either), so the enum would
label the Reminders row "Other" and give it a link symbol.

### 8.4 Email account (`EmailAccountView`)

The mailbox screen is where the app is allowed to look most like a form, because
its job is unambiguous. Three account states, and the distinction between the last
two is the point:

| State | Shown as | Form |
| --- | --- | --- |
| No mailbox configured | heading "Connect a mailbox", empty address | address, server, password |
| Configured + password stored | the address, "N unread messages" | server/mailbox facts, replace, disconnect |
| Configured, **no password in the Keychain** | "Password needed" | password only |

The third state is what a restore-from-backup produces: the non-secret half lives
in `UserDefaults` and survives, the Keychain secret does not. Reporting it as "Not
connected" would send the user to a form that is already filled in and hide the one
thing that has to happen.

**The password is a `SecureField` and is never logged.** It exists only as view
`@State` for the length of the edit and goes straight to the Keychain via
`EmailAccountModel.save(password:)`; the model has no property to store it in. It is
never included in `saveError` (which names the *operation*, not the value), and
`EmailAccount` already restricts its own `description` to host, port and username.
The draft is cleared the instant the save succeeds.

**The rationale is short and only claims what is true:** the password is kept in the
iOS Keychain on this device, never shown again, never written to a log, and leaves
the phone only to sign in over an encrypted connection (the transport is IMAPS — TLS
from the first byte). The "How do I get one?" disclosure names the Gmail path and
says plainly that a normal Google password will not work; it names no other
provider, because a wrong guess at another provider's settings page is worse than
no link.

**The source chip and this screen share one copy source** (`statusLine`), so
"Not connected" / "Checking…" / "N unread messages" cannot drift apart.
| `PermissionPrimerView` (full-screen cover) | `calendar.badge.checkmark` (64pt, `HorizonNext`), "Pulse reads your calendar and reminders to know what needs you.", bullets "Nothing leaves your device" / "No account" / "You can revoke any time", `Continue` (`glassProminent`), `Not now` (`.plain`, `TextSecondary`) | single | `Continue` raises the system prompt; Not now dismisses to 9.2 |
| `SnoozeSheet` (`.height(320)`) | Later today (5 PM), Tonight (8 PM), Tomorrow 9 AM, This weekend (Sat 9 AM), Pick a time… (`DatePicker` `.wheel`) | single | none — the options are the action; a tap snoozes and dismisses |

## 9. Empty states

Real product copy; use exactly these words. All three share one template: 64pt
glyph, `.title2` `.semibold` heading, `.body` `TextSecondary` centred at max width
320pt, buttons, then a `.footnote` `TextTertiary` line.

| State | Glyph · tint | Heading | Body | Buttons · footnote |
| --- | --- | --- | --- | --- |
| **9.1 Genuinely clear** (captured before, nothing needs the user) | `checkmark.circle.fill` · `StatusDone` | "You're all clear" | "Nothing needs you right now. Pulse is watching your calendar and reminders, and you can share a Slack thread, a pull request, or an email here to add it." | `Refresh` (`.bordered`, not prominent) · "Last checked 2 minutes ago" |
| **9.2 Never captured** (no sources connected) | `sparkles` · `HorizonNow` | "Let's see what needs you" | "Connect your calendar and reminders. Pulse reads them on this device and never sends anything anywhere." | `Connect Calendar` (`glassProminent`), `Not now` (`.plain`) · "You can turn sources on or off later in Settings." If only Reminders is available the primary becomes `Connect Reminders`. |
| **9.3 Permission denied** | `calendar.badge.exclamationmark` · `StatusError` | "Pulse can't see your calendar" (the paused source's name: "Pulse can't see your reminders") | "Calendar access is off. Turn it on in Settings and Pulse will fill this board." | `Open Settings` (`.bordered`), `Choose sources` (`.plain`) · "Pulse reads on this device. Nothing leaves it." If reminders still work, those items render above this as a non-blocking banner instead of a full-screen state. |

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

**Widgets.** `.systemSmall` (Pulse Now) shows the Now count in Rounded `.title`, the
top item title over 2 lines and its source glyph. `.systemMedium` shows Now (≤2)
and Next (≤2), title only, with a leading horizon glyph; a row tap deep-links
`thirdhand://item/<id>`. `.systemLarge` shows all four headers with ≤3 rows each (title +
due) and never scrolls or shows all.

**Lock Screen.** `.accessoryRectangular` = Now count plus the first item title on 2
lines. `.accessoryInline` = "Pulse · 2 need you". `.accessoryCircular` = a `Gauge`
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
| 8 | 13" | Home Screen with the small, medium and large Pulse widgets |
| 9 | 6.9" Lock Screen | All three Lock Screen widgets + Live Activity, expanded Dynamic Island |
| 10–11 | 6.9" | Dark appearance of #1 (the tokens differ), then #1 with **Reduce Transparency on** to prove the material fallback |

Devices: #1–#4 and #9–#11 on iPhone 17 Pro Max, #5–#6 on iPhone 17 Pro, #7–#8 on
iPad Pro 13".

Real data only, no lorem ipsum; status bar overridden to 9:41 with full battery and
Wi-Fi; default text size except #6. The plugin mirror is never submitted — there is
no Mac Catalyst target.
