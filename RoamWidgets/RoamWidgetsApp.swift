import SwiftUI
import WidgetKit

@main
struct RoamWidgetsApp: WidgetBundle {
    var body: some Widget {
        #if os(iOS)
        PlayIntent()
        PowerIntent()
        OkIntent()
        MuteIntent()
        VolumeUpIntent()
        VolumeDownIntent()
        #endif

#if !os(watchOS)
        MediumRemoteWidget()
        SmallDpadWidget()
        SmallMediaWidget()
        SmallAppWidget()
#endif

#if !os(macOS)
        SmallVolumeWidget()
        SmallerAppWidget()
        SmallControlWidget()
        #if os(watchOS)
        SmallPowerWidget()
        SmallOkWidget()
        SmallMuteWidget()
        #endif
#endif
    }
}
