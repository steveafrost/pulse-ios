# Third Hand iOS

One board of what needs you — from your Calendar and Reminders, sorted into
**Now / Next / Later / Nice to Know**. Standalone on iOS, and the source of
truth for the [bb](https://github.com/steveafrost/bb-plugin-thirdhand) Third Hand plugin,
which mirrors the same board on your Mac.

## Status

Pre-alpha. Building toward a TestFlight beta. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for milestones and [`docs/DATA-CONTRACT.md`](docs/DATA-CONTRACT.md) for the sync format.

## Layout

```
ThirdHandCore/      Swift package: models, store, capture, sync (no UI)
ThirdHand/          SwiftUI app target
ThirdHandWidgets/   WidgetKit extension
ThirdHandTests/     Unit + UI tests
docs/           Architecture, data contract, design spec
```

The Xcode project is generated — do not edit `ThirdHand.xcodeproj` by hand.

Agent and subagent conventions for this repo: [`.github/AGENT-WORKFLOW.md`](.github/AGENT-WORKFLOW.md).

```sh
brew install xcodegen
xcodegen generate
open ThirdHand.xcodeproj
```

## Develop

```sh
# Core domain (fast, no simulator)
cd ThirdHandCore && swift test

# Full build
xcodebuild -scheme ThirdHand -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## License

MIT
