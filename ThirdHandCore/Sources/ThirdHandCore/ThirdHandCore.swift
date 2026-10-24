import Foundation

/// Namespace for the Third Hand domain layer.
///
/// This package is pure Swift: no EventKit, no filesystem, no UI. It can be
/// tested with `swift test` on macOS with no simulator involved, which is what CI
/// runs on every push.
///
/// Layout (see `docs/ARCHITECTURE.md`):
/// - `Models/`  `ThirdHandItem`, the wire enums, the snapshot envelope, JSON coding.
/// - `Store/`   `ItemStore` (an `actor`) -- the sticky-state machine -- plus
///              `Horizon` derivation and the board sort.
///
/// `STORE.md`-style behaviour is a port of `bb-plugin-thirdhand/lib/store.mjs`; the
/// JSON shape is `docs/DATA-CONTRACT.md` v1.
public enum ThirdHandCore {
    /// The `schemaVersion` this build writes into `snapshot.json`.
    public static let schemaVersion = ThirdHandSnapshot.currentSchemaVersion

    /// Semantic version of the core module, kept in step with the app's
    /// `MARKETING_VERSION`.
    public static let version = "0.1.0"
}
