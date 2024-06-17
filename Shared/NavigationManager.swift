import Foundation
import SwiftUI

@MainActor @Observable
final class NavigationManager {
    var navigationPath: [NavigationDestination] = []

    var last: NavigationDestination? {
        navigationPath.last
    }

    func append(_ destination: NavigationDestination) {
        navigationPath.append(destination)
    }
}
