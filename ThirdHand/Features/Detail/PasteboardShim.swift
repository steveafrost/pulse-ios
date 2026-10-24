#if canImport(UIKit)
import UIKit
#endif

/// Isolates the `UIPasteboard` call so `ItemDetailViewModel` stays testable and
/// the grep for pasteboard use is a single hit.
enum UIPasteboardShim {
    static func write(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
