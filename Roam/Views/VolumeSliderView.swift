#if os(iOS)
    let volumeEpsilon: Float = 0.005

    import Dispatch
    import MediaPlayer
    import os.log
    import SwiftUI

    let globalDefaultVolume: Float = 0.25

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CustomVolumeSlider.self)
    )

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

        class Coordinator: NSObject {
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
        @State var inBackground: Bool = false

        @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool =
            true
        @Environment(\.scenePhase) var scenePhase

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
                logger.info("Resetting volume to clamp value \(newVolume ?? -1), chosen \(targetVolume), unclamped \(audioSession.outputVolume)")
                logger.info("Setting volume to new value \(volume) with target")
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
            .offset(x: -800)
            .onChange(of: volume) { _, newVolume in
                if inBackground || !controlVolumeWithHWButtons {
                    return
                }

                logger.info("Getting volume change \(newVolume) with target")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    logger.info("Setting volume to new value \(volume) with target")
                    volume = targetVolume
                }
            }
            .task(id: inBackground || !controlVolumeWithHWButtons) {
                if inBackground || !controlVolumeWithHWButtons {
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
                    logger.error("Unable to get volume events stream")
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if !controlVolumeWithHWButtons {
                    return
                }
                inBackground = newPhase != .active
                logger.info("New scene phase \(String(describing: newPhase), privacy: .public)")
                if oldPhase != .active, newPhase == .active {
                    self.resetVolume()
                }
            }
            .onAppear {
                logger.info("Appearing")
                if inBackground || !controlVolumeWithHWButtons {
                    return
                }
                self.resetVolume()
            }
        }
    }
#endif
