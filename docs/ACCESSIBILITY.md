# Pulse — Accessibility

The pass for #22. Each line is a check, its method, its result, and the date.
Where an automated check was not feasible in this milestone the manual method is
written down so the check can be repeated on device.

Date of this pass: 2026-10-23. Device: iPhone 17 Pro simulator, iOS 18 SDK path
(Liquid Glass paths are compile-gated to iOS 26 and are exercised separately).

## What the code guarantees

| Check | Method | Result |
| --- | --- | --- |
| No fixed point fonts | `grep -rn 'system(size:' Pulse` (design tokens) | Pass — the only `.system(size:)` uses are the 20pt kind glyph and the 64pt empty-state glyph, both decorative and `accessibilityHidden` |
| Dynamic Type through AX5 | `@Preview` variants at `.dynamicTypeSize(.accessibility5)` for board, detail, empty states and preamble | Pass — titles wrap, detail hides at AX3+, meta line becomes a horizontal scroller at AX2+, chips stop stretching |
| No clipped row text | `.fixedSize(horizontal: false, vertical: true)` on every text block; no fixed row height | Pass |
| Row is one VoiceOver element | `.accessibilityElement(children: .ignore)` + composed label/value/hint | Pass — `BoardItemRow.accessibilityLabel`/`accessibilityValue` implement DESIGN.md §5.3 verbatim |
| Section headers are headers | `.accessibilityAddTraits(.isHeader)`, label "Now, 2 items" | Pass |
| Actions read as outcomes | "Mark done", "More actions for <title>", "Refresh board" | Pass |
| Rotor actions | Done, Snooze, Dismiss, Copy action, Open link, Reopen (conditional) | Pass |
| Hit targets ≥ 44pt | `ThirdHandSpacing.minimumHitTarget` on row controls, chips, FAB, capsule, show-all, banner | Pass |
| Reduce Motion | `ThirdHandMotion` swaps matched geometry for a plain push, drops `.symbolEffect`, makes removal instant, removes the shimmer | Pass — no shimmer exists at all |
| Reduce Transparency | `ThirdHandGlassStyle` substitutes `SurfaceCard` + hairline for every `.glassEffect()` | Pass — `.glassEffect` is only called inside the one modifier's non-reduced branch |
| Bold Text | Weights resolve to `.semibold`; rows have no fixed heights | Pass |
| Increased Contrast | `ThirdHandContrast` lifts chip fill to 22% and separator to 55% | Pass |
| Differentiate without colour | Every tint paired with a glyph and a word; snoozed carries a glyph and "until" | Pass |
| Switch Control | Every action is a `Button` in the tree; the FAB follows the filter bar | Pass |

## Checks that need a device

| Check | Method | Result |
| --- | --- | --- |
| Contrast 4.5:1 for `TextPrimary`/`TextSecondary` over `SurfaceCard` and `SurfaceCanvas`, both appearances | Accessibility Inspector, Color Contrast tool | Not yet run — tokens are the DESIGN.md values, but the assertion needs a live capture |
| VoiceOver announcements after an action ("Done. 3 items left in Now.") | VoiceOver on device, complete a row | Not yet run — the action completes and the row leaves; the count announcement is not written |
| Reduce Transparency visual result | Settings → Accessibility → Display → Reduce Transparency, screenshot | Not yet run — behaviour is implemented, the screenshot is owed for the App Store checklist (#12 items 10–11) |
| Landscape / iPad 720pt cap | Rotate, and run on iPad Pro 13" | Not run — the cap is `frame(maxWidth: 720)` on both the board and detail |

## Craft pass (design/craft review, 2026-10-23)

Re-verified after the typography, colour and Settings/Email changes. Same device
and method as above; every row below was actually run, not reasoned about.

| Check | Method | Result |
| --- | --- | --- |
| The new serif headings scale to AX5 | `simctl ui content_size accessibility-extra-extra-extra-large`, screenshots of board and email screen | Pass — `design: .serif` is a text style, so New York scales exactly as SF does. "Now 5" and "Connect a mailbox" both wrap rather than clip |
| Rows still never clip at AX5 | same run, board screenshot | Pass on clipping — the title takes 3+ lines and grows freely. **However** the FAB overlaps row content at AX5 (see gap 4) |
| Removed kind chip did not remove the kind from VoiceOver | `BoardItemRow` accessibility label/value inspection | Pass — the kind is still announced; only the duplicate *visual* pill was removed |
| Disabled primary action is visibly disabled | email screen with an empty address, screenshot | Pass — this was **broken** and is now fixed: `ThirdHandProminentButtonStyle` ignored `isEnabled`, so a correctly-disabled "Connect" rendered fully saturated red |
| Reduce Motion shows load-in final state immediately | read of `LoadIn.body` (returns content untouched when reduced) + Reduce Motion on in Settings | Pass by construction — there is no animation and no delay to shorten |
| New colour tokens have all three appearances | `RailNeutral.colorset` inspection | Pass — light, dark, and increased contrast are all defined |
| Password field is a `SecureField` and cannot be logged | `EmailAccountView` source + `EmailAccountModel` surface inspection | Pass — the model has no property that can hold the password; `EmailAccount.description` names host/port/username only, asserted in `EmailAccountModelTests` |
| No fixed point fonts added | `grep -rn 'system(size:' ThirdHand/DesignSystem ThirdHand/Features/Settings` | Pass — the new screens use text styles throughout; remaining `.system(size:)` calls are decorative glyphs |

## Known gaps

1. **No UI test target.** The project has `ThirdHandTests` (unit) only. `performAccessibilityAudit()`
   requires an `XCUIApplication` UI test target, so #22's automated audit is deferred
   and replaced by the tables above. Adding `ThirdHandUITests` is the next step.
1a. ~~**The test target cannot be built by the documented command.**~~ **Fixed.**
   `xcodebuild test -scheme ThirdHand` used to fail before running a single test:
   `ThirdHandTests` set neither `GENERATE_INFOPLIST_FILE` nor `INFOPLIST_FILE`, so the
   bundle could not be produced. CI masked it with `CODE_SIGNING_ALLOWED=NO`, which
   nobody would guess. One key in `project.yml` fixes it; the documented command now
   passes unqualified. Flagged here because it is a `project.yml` change made in a
   design pass, and it should be reviewed as such rather than buried.
4. **The FAB overlaps the last row at AX5.** `BoardView.bottomInset` adds a
   size-class constant (up to +290) but the FAB's own height grows faster than that
   at accessibility sizes. Visible in the AX5 board screenshot. It does not clip or
   hide content permanently (the board scrolls), but the FAB sits over the row
   beneath it.
5. **The column of numbers/rails at AX5 is very tall.** Correct, but a 12-item board
   is several screens. This is inherent to AX5 and not worked around by hiding
   content, which would be worse.
6. **The email introductory paragraph is hidden at AX4+** (`EmailAccountView`), so
   the fields are not pushed three screens down. The same facts remain in the
   password rationale and the Settings privacy block, so nothing is only stated
   there — but it is a deliberate omission of body copy, recorded here rather than
   done silently.
2. **Count announcement after completion.** DESIGN.md §10 asks VoiceOver to say
   "Done. 3 items left in Now." The row currently leaves silently; the completion
   flash and collapse are correct, the post-announcement is not implemented.
3. **Switch Control ordering** was reasoned from the view tree, not driven.
