# Third Hand support

Third Hand puts what needs you from your calendar and reminders on one board, in four
horizons: Now, Next, Later, and Nice to Know.

## Contact

- **Bug or feature request:** <https://github.com/steveafrost/thirdhand-ios/issues>
- **Email:** support@steveafrost.com

Please say which iPhone and iOS version you are on, and what you expected to
happen. If the board is wrong rather than broken, a screenshot helps more than a
description.

## Frequently asked

### Third Hand is showing nothing. Is it broken?

Usually not. Third Hand shows only what is on your device, and only what it judges to
need you. Check:

1. **Settings → Third Hand → Calendars** and **Reminders** are both switched on.
2. Your calendar actually has events in the next few days.
3. Tap **Refresh** on the board (or pull down) to run a capture pass.

If your calendar is empty, the board will be empty — Third Hand will not invent items.

### Why does Third Hand want full calendar access?

Reading event titles, times, attendees and notes is what lets it decide that an
invitation needs a reply or that a meeting needs preparation. That is the whole
product. The data is read on your device and is not sent anywhere — see the
[privacy policy](PRIVACY.md).

### Can I use Third Hand without granting calendar or reminders access?

Yes. You can grant either, both, or neither. With neither, the board shows the
connect state and a button that takes you to Settings. Third Hand stays usable; it just
has nothing to show.

### Does my data go to a server?

No. There is no account and no server. Your board is copied to your own private
iCloud container so it can be read on your Mac. Nobody else, including the
developer, can read that copy.

### How do I make it stop syncing to my Mac?

Turn off iCloud for Third Hand in **Settings → [your name] → iCloud → Apps Using
iCloud → Third Hand**, or delete the iCloud data from **Manage Account Storage**.

### Snoozed items are not coming back

Snooze presets are one hour, this evening, and tomorrow morning. If an item is not
back after the preset, check that Third Hand still has calendar/reminder access — iOS
stops background refresh when permission is revoked. Re-granting and opening the
app runs a capture pass immediately.

### Where do closed items go?

To **Recently Closed**, reachable from the clock icon on the board. They stay
there for three days, and any of them can be reopened with a reason. After three
days they are pruned.

### Does Third Hand work on iPad or Mac?

Third Hand is an iPhone app. It is not a Mac Catalyst app and has no iPad layout. The
Mac side is a separate mirror that reads the iCloud snapshot; it is not on the App
Store.

### How do I report something I think is a security problem?

Email **security@steveafrost.com** rather than opening a public issue.

## Privacy

The full policy is in [PRIVACY.md](PRIVACY.md). The one-sentence version: Third Hand
does not collect any data — it reads your calendar and reminders on your device,
and copies your board only to your own private iCloud.
