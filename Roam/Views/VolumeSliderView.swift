#if os(iOS)
    let volumeEpsilon: Float = 0.005

    import Dispatch
    import MediaPlayer
    import os.log
    import SwiftUI

    let globalDefaultVolume: Float = 0.25

    struct CustomVolumeSlider: UIViewRepresentable {
        @Binding var volume: Float
        @Binding var isTouched: Bool

        func makeUIView(context: Context) -> MPVolumeView {
            let volumeView = MPVolumeView(frame: .zero)
            if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                slider.addTarget(
                    context.coordinator,
                    action: #selector(Coordinator.valueChanged(_:)),
                    for: .valueChanged
                )
                slider.addTarget(context.coordinator, action: #selector(Coordinator.touchStarted(_:)), for: .touchDown)
                slider.addTarget(
                    context.coordinator,
                    action: #selector(Coordinator.touchEnded(_:)),
                    for: .touchUpInside
                )
                slider.setThumbImage(UIImage(), for: .normal)
            }
            volumeView.transform = CGAffineTransform(rotationAngle: .pi / -2) // Rotate to vertical

            return volumeView
        }

        func updateUIView(_ view: MPVolumeView, context _: Context) {
            if let slider = view.subviews.first(where: { $0 is UISlider }) as? UISlider, !isTouched {
                slider.value = volume
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        final class Coordinator: NSObject {
            var customVolumeSlider: CustomVolumeSlider

            init(_ customVolumeSlider: CustomVolumeSlider) {
                self.customVolumeSlider = customVolumeSlider
            }

            @MainActor @objc func valueChanged(_ sender: UISlider) {
                customVolumeSlider.volume = sender.value
            }

            @MainActor @objc func touchStarted(_: UISlider) {
                customVolumeSlider.isTouched = true
            }

            @MainActor @objc func touchEnded(_: UISlider) {
                customVolumeSlider.isTouched = false
            }
        }
    }

    struct CustomVolumeSliderOverlay: View {
        private let showSlider: Bool = false
        private let audioSession: AVAudioSession = .sharedInstance()

        @Binding var volume: Float
        @State var targetVolumeSet: Float?
        var changeVolume: (VolumeEvent) -> Void

        @State private var isTouched: Bool = false

        @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool =
            true
        @Environment(\.scenePhase) var scenePhase
        @Environment(\.layoutDirection) var layoutDirection

        var inForeground: Bool {
            return scenePhase == .active
        }

        var targetVolume: Float {
            targetVolumeSet ?? globalDefaultVolume
        }

        func getAudioClamped(_ value: Float) -> Float? {
            if value > 0.75 {
                0.75
            } else if value < 0.25 {
                0.25
            } else {
                value
            }
        }

        func resetVolume() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let newVolume = getAudioClamped(audioSession.outputVolume)
                targetVolumeSet = getAudioClamped(audioSession.outputVolume) ?? targetVolumeSet
                Log.userInteraction.notice("Resetting volume to clamp value \(newVolume ?? -1, privacy: .public), chosen \(targetVolume, privacy: .public), unclamped \(audioSession.outputVolume, privacy: .public)")
                Log.userInteraction.notice("Setting volume to new value \(volume, privacy: .public) with target")
                volume = targetVolume
            }
        }

        var body: some View {
            VStack {
                Spacer()
                HStack {
                    CustomVolumeSlider(volume: $volume, isTouched: $isTouched)
                        .frame(maxHeight: 150)
                    Spacer()
                }
                Spacer()
                Spacer()
                Spacer()
                Spacer()
            }
            .offset(x: layoutDirection == .rightToLeft ? -800 : 800)
            .onChange(of: volume) { _, newVolume in
                guard inForeground && controlVolumeWithHWButtons else {
                    return
                }

                Log.userInteraction.notice("Getting volume change \(newVolume, privacy: .public) with target")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    Log.userInteraction.notice("Setting volume to new value \(volume, privacy: .public) with target")
                    volume = targetVolume
                }
            }
            .task(id: inForeground && controlVolumeWithHWButtons) {
                guard inForeground && controlVolumeWithHWButtons else {
                    return
                }
                do {
                    try await Task.sleep(duration: 0.5)
                } catch {
                    return
                }

                if let stream = await VolumeListener(session: AVAudioSession.sharedInstance()).events {
                    for await volumeEvent in stream {
                        let newVolume = volumeEvent.volume
                        if abs(newVolume - targetVolume) > volumeEpsilon && abs(newVolume - volume) > volumeEpsilon {
                            if newVolume > volume {
                                changeVolume(VolumeEvent(direction: .up, volume: volume))
                            } else {
                                changeVolume(VolumeEvent(direction: .down, volume: volume))
                            }
                        }
                        volume = newVolume
                    }
                } else {
                    Log.userInteraction.error("Unable to get volume events stream")
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                guard controlVolumeWithHWButtons else {
                    return
                }
                Log.userInteraction.notice("New scene phase in volume listener \(String(describing: newPhase), privacy: .public)")
                if oldPhase != .active, newPhase == .active {
                    self.resetVolume()
                }
            }
            .onAppear {
                Log.userInteraction.notice("Volume slider appearing")
                guard inForeground && controlVolumeWithHWButtons else {
                    return
                }
                self.resetVolume()
            }
        }
    }
#endif
