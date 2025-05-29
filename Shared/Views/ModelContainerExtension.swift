import SwiftData
import SwiftUI

struct CheckedModelContainerModifier: ViewModifier {
    let containerResult: Result<ModelContainer, ModelContainerFailureReason>

    @ViewBuilder
    func body(content: Content) -> some View {
        switch containerResult {
        case .success(let container):
            content
                .modelContainer(container)
        case .failure(let failureReason):
            ContainerFailureView(reason: failureReason)
        }
    }
}

extension View {
    public func checkedModelContainer(_ containerResult: Result<ModelContainer, ModelContainerFailureReason>) -> some View {
        modifier(CheckedModelContainerModifier(containerResult: containerResult))
    }
}

struct ContainerFailureView: View {
    let reason: ModelContainerFailureReason

    var body: some View {
        Text("Container failed to load")
    }
}
