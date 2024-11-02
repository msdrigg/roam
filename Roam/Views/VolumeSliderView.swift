#if os(iOS)
    let volumeEpsilon: Float = 0.005

    import Dispatch
    import MediaPlayer
    import os.log
    import SwiftUI

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
        var changeVolume: (VolumeEvent) -> Void

        @State private var isTouched: Bool = false
        @State var targetVolume: Float?
        @State var inBackground: Bool = false

        @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool =
            true
        @Environment(\.scenePhase) var scenePhase

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
                if targetVolume == 0 || targetVolume == nil {
                    logger
                        .info(
                            "Changing empty target from \(String(describing: targetVolume), privacy: .public) to \(audioSession.outputVolume, privacy: .public)"
                        )
                    targetVolume = newVolume
                }

                if inBackground || !controlVolumeWithHWButtons {
                    return
                }

                logger.info("Getting volume change \(volume) with target \(String(describing: targetVolume), privacy: .public)")
                if let tv = targetVolume, volume != tv, !inBackground {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        logger.info("Setting volume to new value \(volume) with target \(tv, privacy: .public)")
                        volume = tv
                    }
                }
            }
            .task(id: inBackground || !controlVolumeWithHWButtons) {
                if inBackground || !controlVolumeWithHWButtons {
                    return
                }
                if let stream = await VolumeListener(session: AVAudioSession.sharedInstance()).events {
                    for await volumeEvent in stream {
                        let volume = volumeEvent.volume
                        if let tv = targetVolume {
                            if abs(volume - tv) > volumeEpsilon {
                                if volume > tv {
                                    changeVolume(VolumeEvent(direction: .up, volume: volume))
                                } else {
                                    changeVolume(VolumeEvent(direction: .down, volume: volume))
                                }
                            }
                        }
                    }
                } else {
                    logger.error("Unable to get volume events stream")
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                inBackground = newPhase != .active
                logger.info("New scene phase \(String(describing: newPhase), privacy: .public)")
                if oldPhase != .active, newPhase == .active {
                    logger
                        .info(
                            "Changing target from \(String(describing: targetVolume), privacy: .public) to \(audioSession.outputVolume)"
                        )
                    targetVolume = audioSession.outputVolume
                }
            }
        }
    }
#endif
