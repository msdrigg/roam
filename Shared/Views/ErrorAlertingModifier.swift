import SwiftUI

struct ErrorAlertingModifier: ViewModifier {
    @Binding var error: Error?
    let message: String
    
    func body(content: Content) -> some View {
        content
            .alert(message, isPresented: Binding<Bool>(
                get: { error != nil },
                set: { _ in error = nil }
            )) {
                Button("OK") { error = nil }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
    }
    
    private var errorMessage: String? {
        guard let error = error else { return nil }
        
        if let localizedError = error as? LocalizedError {
            var parts: [String] = []
            
            if let errorDescription = localizedError.errorDescription {
                parts.append(errorDescription)
            }
            
            if let recoverySuggestion = localizedError.recoverySuggestion {
                parts.append(recoverySuggestion)
            }
            
            return parts.isEmpty ? error.localizedDescription : parts.joined(separator: "\n\n")
        } else {
            return error.localizedDescription
        }
    }
}

extension View {
    func alertingError(message: String, error: Binding<Error?>) -> some View {
        modifier(ErrorAlertingModifier(error: error, message: message))
    }
}