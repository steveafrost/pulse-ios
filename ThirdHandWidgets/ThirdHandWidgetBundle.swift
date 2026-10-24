import SwiftUI
import WidgetKit

/// The extension's `@main`: every widget surface Third Hand ships, in one bundle.
///
/// One bundle rather than three targets because a widget extension is the unit the
/// system installs and the user adds from; three extensions would mean three entries
/// in the gallery for one app.
@main
struct ThirdHandWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // #29 Home Screen
        ThirdHandHomeWidget()
        // #30 Lock Screen
        ThirdHandAccessoryWidget()
        // #31 Live Activity
        ImminentMeetingActivityWidget()
    }
}
