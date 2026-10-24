# Device testing

What a simulator cannot prove, and how to prove it once.

## Why this document exists

Every claim in `docs/RELEASE-READINESS.md` was verified on a simulator. As of this
writing **no physical iOS device has run this build** — `xcrun devicectl list devices`
lists only simulators and the host Mac. That is a real coverage gap, not a
scheduling detail, and the honest status of each item below is recorded rather than
implied.

A simulator differs from a phone in ways that matter specifically here:

| Area | Simulator | Device |
| --- | --- | --- |
| iCloud Drive container | Usually `nil` | Resolves when signed in |
| EventKit prompts | Appear, but permissions reset per install | Persist; real denial paths |
| Background refresh | Not scheduled; needs a debugger kick | Real budget, real throttling |
| Live Activities | Renders | Renders on a real Lock Screen; user can disable |
| Battery / memory | Not representative | Representative |
| Dynamic Type at AX5 | Layout only | Layout plus real legibility |

## Recording evidence

For each step, record: a screenshot, the Console output filtered to
`subsystem:com.steveafrost.thirdhand`, and the wall-clock time. Anything not recorded
did not happen.

Attach evidence to the release checklist issue. A step marked pass without
evidence is treated as unverified.

---

## 1. iCloud container resolution

**Why it matters.** The Mac mirror only works through the iCloud ubiquity container
`iCloud.com.steveafrost.thirdhand`. On a simulator this is `nil` almost always, so the
entire transport is untested against a real filesystem.

1. Sign in to iCloud on the device, with **iCloud Drive ON**.
2. Launch Third Hand. Open Settings (in-app) → the sync line must read a connected state,
   not "Not connected to iCloud".
3. **Pass:** sync line names the Mac or shows a connected/publishing state.
   **Fail:** "Not connected to iCloud" while the device is demonstrably signed in —
   that means an entitlement or container-identifier problem, not an account one.
4. Now turn **iCloud Drive OFF** (Settings → your name → iCloud → iCloud Drive).
5. Relaunch Third Hand. **Pass:** the app still opens, the board renders from local
   storage, and the sync line clearly says iCloud is not connected. **Fail:** any
   crash, hang, or a board that silently shows stale data as if live.
6. Turn iCloud Drive back ON. **Pass:** sync recovers without a reinstall.

Record the exact wording shown in each state.

## 2. Mac mirror round trip, and its latency

**Why it matters.** The plugin reads `snapshot.json` and writes `commands.jsonl`. This
was proven against a file-based container in tests, never against real iCloud
propagation, whose latency is the number a user actually feels.

1. On the Mac, start the plugin and confirm it is watching
   `~/Library/Mobile Documents/iCloud~com~steveafrost~thirdhand/Documents/ThirdHand/`.
2. On the device, mark an item done.
3. **Measure the time** until the Mac's `snapshot.json` reflects it. Use a stopwatch;
   record seconds. Do this three times and report all three — the spread matters.
4. On the Mac, mark an item done through the plugin. Measure how long until the
   device's board changes. Record three times.
5. **Turn off the Mac's network.** Mark items done on the device. Turn the Mac's
   network back on. **Pass:** the Mac catches up and applies the queued commands.
   **Fail:** commands lost, or applied twice (check `commands.ack.jsonl` for duplicate
   application by id).

**Known numbers to beat:** propagation under 10 s is good; 10–60 s is acceptable but
worth noting; over 60 s is a product problem.

## 3. EventKit permissions on real hardware

1. Fresh install. Open Third Hand → grant Calendar when prompted → confirm items appear.
2. Delete the app. Reinstall. Deny Calendar. **Pass:** the board explains what is
   missing and offers a route to Settings. **Fail:** an empty board with no
   explanation, or a crash.
3. Go to Settings → Third Hand → enable Calendar. Return to the app. **Pass:** capture
   resumes without a relaunch.
4. Repeat for Reminders, including denying one and granting the other.
5. Enable **Screen Time content restrictions** that restrict calendar access
   (Settings → Screen Time → Content & Privacy → Calendars). **Pass:** the affected
   source is reported as unavailable, not as an error, and the other source still
   works. Record the wording.

## 4. Background refresh over hours

**Why it matters.** `BGAppRefreshTask` (`com.steveafrost.thirdhand.refresh`) cannot be
scheduled on demand. Its real behaviour is a budget iOS grants, and only a device
over hours reveals whether the board stays fresh.

1. Fully charge the device. Note the time.
2. Use Third Hand normally, then leave it backgrounded for **at least 4 hours** without
   opening it.
3. At the end, check the timestamp on the board's capture capsule — it must be
   recent, not the time you backgrounded it.
4. Check battery drain in Settings → Battery, filtering to Third Hand. Record the
   percentage over the window. More than ~3% attributable to Third Hand is worth
   investigating.
5. **Pass:** the board refreshed in the background and drain is modest.
   **Fail:** no refresh at all past 4 h (report it — iOS may be throttling because
   the app never appeared in the user's habits), or drain over 5%.

## 5. Live Activities and Dynamic Island

1. Create a calendar event starting in 30 minutes. Confirm the Live Activity starts.
2. Lock the device. **Pass:** the Lock Screen activity shows the right meeting and
   countdown.
3. On a Dynamic Island device, check all presentations: compact leading/trailing,
   minimal, expanded.
4. End the meeting time. **Pass:** the activity ends cleanly, not stuck.
5. Go to Settings → Third Hand → **turn Live Activities OFF**. Trigger another imminent
   meeting. **Pass:** no crash, no stuck spinner, and the app behaves as documented.
   **Fail:** a crash or a phantom activity.

## 6. Real-screen legibility and VoiceOver

1. Set text size to **AX5** (Settings → Accessibility → Display & Text Size → Larger
   Text, maximum).
2. Walk every screen: board, detail, closed review, snooze sheet, empty states, error
   states. **Pass:** no clipped or truncated text that loses meaning; no horizontal
   scrolling required.
3. Enable VoiceOver. Navigate the board with the rotor set to **Actions** and
   **Headings**. **Pass:** every row announces what it is, its state, and what
   double-tapping does; no control announces a bare SF Symbol name; the section
   headings are reachable by rotor.
4. Complete a full capture → mark-done → review cycle with VoiceOver alone.

## 7. Widgets

1. Add the Home Screen widget (small, medium, large). **Pass:** content matches the
   board and refreshes.
2. Add the Lock Screen accessory widget (circular, rectangular, inline).
3. Tap the widget. **Pass:** opens the app to the right place.
4. Mark an item done in the app. **Pass:** the widget updates without a manual
   refresh within a reasonable interval.

---

## Current status

| Section | Status |
| --- | --- |
| 1. iCloud resolution | Partially verified on simulator — the `nil` path is unit-tested and degrades to "Not connected to iCloud". The **signed-in** path is **unverified**. |
| 2. Mac round trip | Protocol-verified against a file container; **real iCloud latency unmeasured**. |
| 3. EventKit | Prompt, deny, and recovery paths verified on simulator; **restricted-mode unverified**. |
| 4. Background refresh | Registration and handler wiring verified; **scheduling unverified**. |
| 5. Live Activities | Verified on simulator; **disabled-by-user path and real Lock Screen unverified**. |
| 6. AX5 / VoiceOver | Layout audited at AX5 on simulator; **real-screen legibility unverified**. |
| 7. Widgets | Registered and rendered on simulator; **device refresh unverified**. |

Nothing in this table is a "pass" on hardware. Update it as items are recorded, and
delete the row's caveat only when evidence exists.
