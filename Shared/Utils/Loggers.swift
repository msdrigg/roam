import OSLog

public enum Log {
    // Used for watch connectivity
    public static let watch = Logger(subsystem: getLogSubsystem(), category: "Watch")
    // Used for notification events
    public static let notifications = Logger(subsystem: getLogSubsystem(), category: "Notifications")
    // Used for backend events and status
    public static let backend = Logger(subsystem: getLogSubsystem(), category: "Backend")
    // Used for UI interface
    public static let interface = Logger(subsystem: getLogSubsystem(), category: "Interface")
    // Used for network status and permissions logs
    public static let network = Logger(subsystem: getLogSubsystem(), category: "Network")
    // Used for data loading, storage and other information
    public static let data = Logger(subsystem: getLogSubsystem(), category: "Data")
    // Used for all view and app lifecycle related events
    public static let lifecycle = Logger(subsystem: getLogSubsystem(), category: "Lifecycle")
    // Used for the headphones mode and related events (latency listener included)
    public static let headphones = Logger(subsystem: getLogSubsystem(), category: "Headphones")
    // Used for the scanning module and related events
    public static let scanning = Logger(subsystem: getLogSubsystem(), category: "Scanning")
    // Used for the device connection module and related events
    public static let connection = Logger(subsystem: getLogSubsystem(), category: "Connection")
    // Used for direct response to users clicking buttons or performing actions
    public static let userInteraction = Logger(subsystem: getLogSubsystem(), category: "UserInteraction")

    public static func getLogSubsystem() -> String {
        return Bundle.main.bundleIdentifier ?? "com.msdrigg.roam"
    }

}
