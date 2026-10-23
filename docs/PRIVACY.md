# Pulse privacy policy

**Last updated: 23 October 2026** — applies to Pulse for iOS, version 0.1.0 and later.

Pulse is made by Steve Frost. This page explains, in full, what Pulse does with
your information. It is short because Pulse does very little.

## The short version

Pulse does not collect your data. It has no account, no server, no analytics and
no third-party SDKs. It reads the calendar and reminders on your iPhone and shows
them back to you. The only place your board is copied to is your own private
iCloud, so it can also be read on your Mac.

## What Pulse reads

Pulse asks for two permissions, both optional and both revocable at any time in
**Settings → Pulse**:

- **Calendar** — to see your events, so it can show the ones that need a reply, a
  decision or your attention.
- **Reminders** — to see your reminders, so overdue and due-today items appear on
  your board.

Pulse reads only what those frameworks expose. It does not read your email, your
contacts, your location, your photos, your microphone, your camera, or anything
else. It does not use the Advertising Identifier.

## Where your data goes

Nowhere. Specifically:

- **On your device.** Calendar and reminder data is read, ranked and displayed on
  the device. It is never transmitted to Steve Frost or to any third party.
- **Your own iCloud.** So the board can be read on your Mac, Pulse writes a
  snapshot of the board to `iCloud.com.steveafrost.pulse` — a container inside
  your own private iCloud account, covered by your Apple ID and your Apple iCloud
  terms. Steve Frost has no access to it, holds no keys for it, and operates no
  server that could read it.
- **Nowhere else.** There is no analytics service, no crash reporter, no
  advertising network, no data broker, no third-party library that phones home.

Pulse makes no network requests of its own. Every sync is Apple's own iCloud
daemon moving a file within your account.

## What Pulse does not do

- No account, sign-up, email address, password or profile.
- No tracking, advertising or advertising identifier.
- No analytics, telemetry, or usage statistics.
- No third-party SDKs of any kind.
- No selling, sharing or transferring of data — there is none to sell.
- No access to your data by the developer, at any time, for any reason.

## Keeping and deleting

Because Pulse stores nothing off your device apart from your own iCloud copy,
there is nothing for us to retain. To delete everything Pulse has stored:

1. Delete the app from your iPhone. This removes its on-device data.
2. To also remove the iCloud copy: **Settings → [your name] → iCloud → Manage
   Account Storage → Pulse → Delete Data**.

Deleting the app immediately stops all processing; nothing is retained anywhere
else.

## Children

Pulse is rated 4+ and is not directed at children. It collects no data from
anyone, of any age. There is nothing to consent to.

## Changes to this policy

If Pulse ever changes in a way that affects this policy, the change will be made
in this file in the public repository, with the date at the top updated. Because
Pulse collects nothing, we do not expect meaningful changes; the version history
of this file is the record.

## Contact

Questions about privacy, or anything in this policy:

- Open an issue: <https://github.com/steveafrost/pulse-ios/issues>
- Email: **privacy@steveafrost.com**

This policy applies to the Pulse iOS app (bundle id `com.steveafrost.pulse`) and
its widget extension (`com.steveafrost.pulse.widgets`).
