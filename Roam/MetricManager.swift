import MetricKit

final class RoamMetricManager: NSObject, MXMetricManagerSubscriber, Sendable {
    override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payload: [MXDiagnosticPayload]) {
        Log.backend.notice("Getting \(payload.count, privacy: .public) payloads in metric manager")
        if payload.contains(where: { payload in
            payload.crashDiagnostics?.isEmpty == false
        }) {
            let payloadData = payload.filter { $0.crashDiagnostics?.isEmpty == false }.map{ $0.jsonRepresentation() }
            Log.backend.notice("Sending \(payloadData.count, privacy: .public) crash diagnostics reports...")
            Task {
                await uploadMetricKitDiagnostics(payloadData)
            }
        }
    }

    private func uploadMetricKitDiagnostics(_ diagnostics: [Data]) async {
        Log.backend.notice("Sending \(diagnostics.count, privacy: .public) diagnostics reports...")
        for (idx, diagnosticsJSON) in diagnostics.enumerated() {
            Log.backend.notice("Sending diagnostics report...")
            do {
                let hash = fastHashData(data: diagnosticsJSON)
                let upload = AttachmentUpload(filename: "MetricDiagnostics-\(idx).json", dataHash: hash, dataSize: Int64(diagnosticsJSON.count), contentType: "application/json", id: UUID().uuidString)
                _ = try await sendMessageDirect(message: ":ninja: Diagnostics Reported", attachment: upload, attachmentData: diagnosticsJSON).get()
                Log.backend.notice("Send diagnostics successfully")
            } catch {
                Log.backend.notice("Failed to send diagnostics: \(error, privacy: .public)")
            }
        }
        // Reporting diagnostics as well
        let logs = await getDebugInfo()

        if let data = trimmedDebugInfoIfNeeded(logs) {
            let hash = fastHashData(data: data)

            let upload = AttachmentUpload(
                filename: "MetricDiagnostics-Extra.json",
                dataHash: hash,
                dataSize: Int64(data.count),
                contentType: "application/json",
                id: UUID().uuidString,
                pairedMessages: [DiagnosticsImport.getDebugLogMessageString(logs)]
            )
            do {
                _ = try await sendMessageDirect(message: ":ninja: Diagnostics Reported", attachment: upload, attachmentData: data).get()
                Log.backend.notice("Send extra diagnostics successfully")
            } catch {
                Log.backend.notice("Failed to send extra diagnostics: \(error, privacy: .public)")
            }
        } else {
            Log.backend.warning("No additional device diagnostics to send.")
        }
    }
}
