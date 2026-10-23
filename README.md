# Pulse iOS

One board of what needs you — from your Calendar and Reminders, sorted into
**Now / Next / Later / Nice to Know**. Standalone on iOS, and the source of
truth for the [bb](https://github.com/steveafrost/bb-plugin-pulse) Pulse plugin,
which mirrors the same board on your Mac.

## Status

Pre-alpha. Building toward a TestFlight beta. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for milestones and [`docs/DATA-CONTRACT.md`](docs/DATA-CONTRACT.md) for the sync format.

## Layout

```
PulseCore/      Swift package: models, store, capture, sync (no UI)
Pulse/          SwiftUI app target
PulseWidgets/   WidgetKit extension
PulseTests/     Unit + UI tests
docs/           Architecture, data contract, design spec
```

The Xcode project is generated — do not edit `Pulse.xcodeproj` by hand.

```sh
brew install xcodegen
xcodegen generate
open Pulse.xcodeproj
```

## Develop

```sh
# Core domain (fast, no simulator)
cd PulseCore && swift test

# Full build
xcodebuild -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## License

MIT
