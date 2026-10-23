import Foundation

/// Namespace for the Pulse domain layer.
///
/// M1 populates this package with models, the `ItemStore` actor, capture
/// sources and the sync protocol. For now it exists so the app, widget and
/// test targets can link against a real module while the project scaffolding
/// is verified end to end.
public enum PulseCore {
    /// Semantic version of the core module, kept in step with the app's
    /// `MARKETING_VERSION`.
    public static let version = "0.1.0"
}
