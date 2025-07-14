import Foundation

extension DispatchQueue {
    /// High-priority queue for network-related operations
    static let network = DispatchQueue(label: "com.msdrigg.roam.network", qos: .userInitiated, attributes: .concurrent)

    /// High-priority queue for computation-intensive operations
    static let computation = DispatchQueue(label: "com.msdrigg.roam.computation", qos: .userInitiated, attributes: .concurrent)
}
