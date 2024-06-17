import SwiftUI
import WidgetKit

@main
struct RoamWidgetsApp: WidgetBundle {
    var body: some Widget {
#if !os(watchOS)
        MediumRemoteWidget()
        SmallDpadWidget()
        SmallMediaWidget()
        SmallAppWidget()
#endif

#if !os(macOS)
        if #available(watchOS 11.0, iOS 17.0, visionOS 1.0, *) {
            SmallVolumeWidget()
            SmallerAppWidget()
            SmallControlWidget()
            #if os(watchOS)
            SmallPowerWidget()
            SmallOkWidget()
            SmallMuteWidget()
            #endif
        }
#endif
    }
}
