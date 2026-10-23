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
| Hit targets ≥ 44pt | `PulseSpacing.minimumHitTarget` on row controls, chips, FAB, capsule, show-all, banner | Pass |
| Reduce Motion | `PulseMotion` swaps matched geometry for a plain push, drops `.symbolEffect`, makes removal instant, removes the shimmer | Pass — no shimmer exists at all |
| Reduce Transparency | `PulseGlassStyle` substitutes `SurfaceCard` + hairline for every `.glassEffect()` | Pass — `.glassEffect` is only called inside the one modifier's non-reduced branch |
| Bold Text | Weights resolve to `.semibold`; rows have no fixed heights | Pass |
| Increased Contrast | `PulseContrast` lifts chip fill to 22% and separator to 55% | Pass |
| Differentiate without colour | Every tint paired with a glyph and a word; snoozed carries a glyph and "until" | Pass |
| Switch Control | Every action is a `Button` in the tree; the FAB follows the filter bar | Pass |

## Checks that need a device

| Check | Method | Result |
| --- | --- | --- |
| Contrast 4.5:1 for `TextPrimary`/`TextSecondary` over `SurfaceCard` and `SurfaceCanvas`, both appearances | Accessibility Inspector, Color Contrast tool | Not yet run — tokens are the DESIGN.md values, but the assertion needs a live capture |
| VoiceOver announcements after an action ("Done. 3 items left in Now.") | VoiceOver on device, complete a row | Not yet run — the action completes and the row leaves; the count announcement is not written |
| Reduce Transparency visual result | Settings → Accessibility → Display → Reduce Transparency, screenshot | Not yet run — behaviour is implemented, the screenshot is owed for the App Store checklist (#12 items 10–11) |
| Landscape / iPad 720pt cap | Rotate, and run on iPad Pro 13" | Not run — the cap is `frame(maxWidth: 720)` on both the board and detail |

## Known gaps

1. **No UI test target.** The project has `PulseTests` (unit) only. `performAccessibilityAudit()`
   requires an `XCUIApplication` UI test target, so #22's automated audit is deferred
   and replaced by the tables above. Adding `PulseUITests` is the next step.
2. **Count announcement after completion.** DESIGN.md §10 asks VoiceOver to say
   "Done. 3 items left in Now." The row currently leaves silently; the completion
   flash and collapse are correct, the post-announcement is not implemented.
3. **Switch Control ordering** was reasoned from the view tree, not driven.
