import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// On-device placement, using the system language model (Apple Intelligence).
///
/// **Why this is gated at iOS 26.** `FoundationModels` requires iOS 26.0, which is
/// also the app's deployment target, so the type only exists from 26 up. It still
/// does nothing on hardware that cannot run it: `SystemLanguageModel` reports
/// `.deviceNotEligible` on anything below A17 Pro, and there the advisor is simply
/// absent and `PlacementPolicy` falls back to the deterministic rules -- the board
/// is placed by dates and priority, exactly as before. Nothing is degraded silently:
/// `availabilityNote` says which case the user is in, and the debug screen shows it.
/// The iOS 26 floor is not a guarantee the model runs; eligibility is hardware, not
/// OS version.
///
/// **Why the prompt looks like this.** The model is given one narrow question per
/// batch and told to answer with an index, a bucket and a short reason. It is
/// explicitly told that leaving things alone is the normal answer, because a model
/// asked to "prioritise" will always find everything urgent -- which is the exact
/// failure this exists to fix. Its output is validated: an unknown index, a missing
/// bucket, or a promote into Now for something weeks away is discarded.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct OnDevicePlacementAdvisor: PlacementAdvising {
    /// How the model's judgement is shaped. Small and typed, so the reply is parsed
    /// by the runtime rather than by string splitting.
    @Generable
    struct Verdicts {
        @Guide(description: "One verdict for every item listed. Never omit an item.")
        var items: [Verdict]

        @Generable
        struct Verdict {
            @Guide(description: "The number of the item this verdict is about.")
            var index: Int
            @Guide(description: "now, next, or later.", .anyOf(["now", "next", "later"]))
            var horizon: String
            @Guide(description: "At most 12 words, addressed to the user, saying why.")
            var reason: String
        }
    }

    /// Batches are capped so one prompt cannot blow the context window. Sixteen
    /// two-line items is comfortably inside it and keeps latency under a few seconds
    /// on a phone.
    public static let maxBatchSize = 16

    /// The reason string the model gives is shown on a card, so it is bounded rather
    /// than trusted. Longer text is truncated at a word boundary. Owned by
    /// `PlacementValidation` so the limit is testable without a model.
    public static var maxReasonLength: Int { PlacementValidation.maxReasonLength }

    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    /// Whether the model can actually run right now, and why not if it cannot.
    /// Checked before every batch: availability changes at runtime (the user can
    /// turn Apple Intelligence off, or the model can still be downloading).
    public var availabilityNote: String {
        switch model.availability {
        case .available:
            return "on-device model available"
        case .unavailable(let reason):
            return Self.describe(reason)
        @unknown default:
            return "on-device model unavailable"
        }
    }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "this device does not support Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off in Settings"
        case .modelNotReady:
            return "the on-device model is still downloading"
        @unknown default:
            return "on-device model unavailable"
        }
    }

    public func advise(
        _ candidates: [PlacementCandidate],
        at instant: Date,
        calendar: Calendar
    ) async -> [PlacementAdvice] {
        guard !candidates.isEmpty else { return [] }
        guard case .available = model.availability else { return [] }

        var advice: [PlacementAdvice] = []
        for batch in stride(from: 0, to: candidates.count, by: Self.maxBatchSize).map({
            Array(candidates[$0 ..< min($0 + Self.maxBatchSize, candidates.count)])
        }) {
            advice += await adviseBatch(batch)
        }
        return advice
    }

    private func adviseBatch(_ batch: [PlacementCandidate]) async -> [PlacementAdvice] {
        let session = LanguageModelSession(
            model: model,
            instructions: Self.instructions
        )
        do {
            let response = try await session.respond(
                to: Self.prompt(for: batch),
                generating: Verdicts.self
            )
            return Self.sanitize(response.content.items, against: batch)
        } catch {
            // Any generation failure (guardrail, context, cancelled) means "no
            // opinion". Placement must never be why the board does not load.
            return []
        }
    }

    /// Turns the model's raw verdicts into advice that is safe to apply.
    ///
    /// The rules themselves live in `PlacementValidation`, which has no availability
    /// requirement and is therefore testable without a model. This is the thin
    /// adapter that converts the generated type into the validated one.
    static func sanitize(
        _ verdicts: [Verdicts.Verdict],
        against batch: [PlacementCandidate]
    ) -> [PlacementAdvice] {
        PlacementValidation.sanitize(
            verdicts.map {
                PlacementValidation.RawVerdict(
                    index: $0.index,
                    horizon: $0.horizon,
                    reason: $0.reason
                )
            },
            against: batch
        )
    }

    static let instructions = """
        You place items on a personal task board. The board has four columns: now \
        (needs the user today), next (the next few days), later (beyond that), and \
        nice to know (informational).

        You are shown items that deterministic rules already placed in now or next, \
        along with the rule that put them there. Your job is to catch placements the \
        rules got wrong, especially items sitting in now that are not actually \
        pressing.

        Leaving an item where it is, is the normal answer. Most items are placed \
        correctly. Only move something when the title and its dates give you a clear \
        reason to disagree with the rule.

        Things that are NOT pressing, even when overdue: routine upkeep that has \
        clearly been ignored for a long time, things with no deadline that are \
        merely informational, and anything the title suggests is a recurring chore \
        rather than a one-off commitment. Things that ARE pressing: a person waiting \
        on the user, money or legal dates, travel, and anything due today that cannot \
        be done later.

        Never put an item in nice to know.
        """

    /// The batched question. Built by `PlacementValidation.prompt` so it can be
    /// asserted without a model -- in particular that it never leaks an item id.
    static func prompt(for batch: [PlacementCandidate]) -> String {
        PlacementValidation.prompt(for: batch)
    }
}

#endif
