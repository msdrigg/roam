import AVFoundation
import AudioToolbox

extension OSStatus {
    var audioConverterErrorDescription: String {
        switch self {
// Audio Codec
        case kAudioCodecBadPropertySizeError:
            return "Audio codec bad property size error"
        case kAudioCodecIllegalOperationError:
            return "Audio codec illegal operation error"
        case kAudioCodecNotEnoughBufferSpaceError:
            return "Audio codec not enough buffer space error"
        case kAudioCodecStateError:
            return "Audio codec state error"
        case kAudioCodecUnknownPropertyError:
            return "Audio codec unknown property error"
        case kAudioCodecUnspecifiedError:
            return "Audio codec unspecified error"
        case kAudioCodecUnsupportedFormatError:
            return "Audio codec unsupported format error"
        case kAudioCodecBadDataError:
            return "Audio codec bad data error"
// Audio Convertor
        case kAudioConverterErr_OperationNotSupported:
            return "Operation not supported"
        case kAudioConverterErr_PropertyNotSupported:
            return "Property not supported"
        case kAudioConverterErr_InvalidInputSize:
            return "Invalid input size: byte size is not an integer multiple of the frame size"
        case kAudioConverterErr_InvalidOutputSize:
            return "Invalid output size"
        case kAudioConverterErr_UnspecifiedError:
            return "Unspecified error"
        case kAudioConverterErr_BadPropertySizeError:
            return "Bad property size error"
        case kAudioConverterErr_RequiresPacketDescriptionsError:
            return "Requires packet descriptions"
        case kAudioConverterErr_InputSampleRateOutOfRange:
            return "Input sample rate out of range"
        case kAudioConverterErr_OutputSampleRateOutOfRange:
            return "Output sample rate out of range"
#if !os(macOS)
        case kAudioConverterErr_HardwareInUse:
            return "Hardware in use"
        case kAudioConverterErr_NoHardwarePermission:
            return "No hardware permission"
#endif
        default:
            return "Unknown OSStatus (\(self))"
        }
    }
}

final class RoamDecoder {
    enum Error: Swift.Error {
        case badArgument
        case badInputBuffer
        case badPCMBuffer
        case notConcealmentPacket(UInt32)
        case codecError(OSStatus)
    }

    public let outputFormat: AVAudioFormat
    private let inputFormat: AVAudioFormat
    private var codec: AudioCodec?
//    private let converter: AVAudioConverter

    public init(opusFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws {
        self.outputFormat = outputFormat
        guard opusFormat.isValidOpusPCMFormat else { throw Error.badArgument }
        var inDesc = opusFormat.streamDescription.pointee
        inDesc.mFormatID = kAudioFormatOpus
        guard let inputFmt = AVAudioFormat(streamDescription: &inDesc) else { throw Error.badArgument }
        self.inputFormat = inputFmt
//        guard let conv = AVAudioConverter(from: inputFmt, to: outputFormat) else { throw Error.badArgument }
//        self.converter = conv
        var outDesc = opusFormat.streamDescription.pointee
        var codecDescription = AudioComponentDescription(
            componentType: kAudioDecoderComponentType,
            componentSubType: kAudioFormatOpus,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &codecDescription) else {
            Log.headphones.notice("No opus decoder on device found")
            throw Error.codecError(-1)
        }

        var instance: AudioComponentInstance?
        let audioComponentStatus = AudioComponentInstanceNew(component, &instance)
        guard audioComponentStatus == noErr, let decoderInstance: AudioCodec = instance else {
            Log.headphones.warning("Error creating opus decoder: \(audioComponentStatus.audioConverterErrorDescription, privacy: .public)")
            throw Error.codecError(audioComponentStatus)
        }
//        let inDesc = AudioStreamBasicDescription(
//            mSampleRate: opusFormat.sampleRate,
//            mFormatID: kAudioFormatOpus,
//            mFormatFlags: 0,
//            mBytesPerPacket: 0,
//            mFramesPerPacket: 441,
//            mBytesPerFrame: 0,
//            mChannelsPerFrame: 2,
//            mBitsPerChannel: <#T##UInt32#>,
//            mReserved: <#T##UInt32#>
//        )
//
        let audioCodecInitializeStatus = AudioCodecInitialize(decoderInstance, &inDesc, &outDesc, nil, 0)
        guard audioCodecInitializeStatus == noErr else {
            Log.headphones.warning("Error initializing opus decoder: \(audioCodecInitializeStatus.audioConverterErrorDescription, privacy: .public)")
            throw Error.codecError(audioCodecInitializeStatus)
        }
//        Log.headphones.notice("Starting with indesc \(inDesc), outdesc \(outDesc)")
        self.codec = decoderInstance
    }

    deinit {
        if let c = codec {
            AudioCodecUninitialize(c)
            AudioComponentInstanceDispose(c)
        }
    }

    public func reset() {
        if let c = codec { AudioCodecReset(c) }
//        converter.reset()
    }

    private func encodeInput(_ input: Data) throws {
        guard let codec = codec else { throw Error.badArgument }
        try input.withUnsafeBytes { raw in
            guard let inDataPointer = raw.baseAddress else {
                throw Error.badInputBuffer
            }
            var ioDataBytes = UInt32(truncatingIfNeeded: input.count)
            var ioInNumberPackets: UInt32 = 1
            let inStatus = AudioCodecAppendInputData(codec, inDataPointer, &ioDataBytes, &ioInNumberPackets, nil)
            if ioInNumberPackets == 0 || ioDataBytes != input.count || inStatus != noErr {
                throw Error.codecError(inStatus)
            }
        }
    }

    private func decodeAvailablePacket() throws -> (AVAudioPCMBuffer, UInt32) {
        guard let codec = codec else { throw Error.badArgument }
        var ioOutNumberPackets: UInt32 = 1

        var codecStatus: UInt32 = 0
        let ioOutBufferList = AudioBufferList.allocate(maximumBuffers: 1)

        let outStatus = AudioCodecProduceOutputBufferList(
            codec,
            ioOutBufferList.unsafeMutablePointer,
            &ioOutNumberPackets,
            nil,
            &codecStatus
        )

        if ioOutNumberPackets == 0 || outStatus != noErr {
            throw Error.codecError(outStatus)
        }

        Log.headphones.notice("Decoded \(ioOutNumberPackets) packets with status \(outStatus) and codecStatus \(codecStatus)")

        let avAudioBuffer = try catchObjc {
            return AVAudioPCMBuffer(pcmFormat: outputFormat, bufferListNoCopy: ioOutBufferList.unsafePointer, deallocator: { _ in
                free(ioOutBufferList.unsafeMutablePointer)
            })
        }

        guard let avAudioBuffer else {
            throw Error.badPCMBuffer
        }
        return (avAudioBuffer, codecStatus)
    }

    public func decode(_ input: Data) throws -> AVAudioPCMBuffer {
        try self.encodeInput(input)
        return try self.decodeAvailablePacket().0
    }

    public func decodeLossConcealment() throws -> AVAudioPCMBuffer {
        let (packet, status) = try self.decodeAvailablePacket()
        if status != kAudioCodecProduceOutputPacketSuccessConcealed {
            throw Error.notConcealmentPacket(status)
        }
        return packet
    }
}
// public extension Opus {
//    final class RoamDecoder {
//        let format: AVAudioFormat
//        let decoder: OpaquePointer
//
//        public init(format: AVAudioFormat, application _: Application = .audio) throws {
//            if !format.isValidOpusPCMFormat {
//                throw Opus.Error.badArgument
//            }
//
//            self.format = format
//
//            // Initialize Opus decoder
//            var error: Opus.Error = .ok
//            decoder = opus_decoder_create(Int32(format.sampleRate), Int32(format.channelCount), &error.rawValue)
//            if error != .ok {
//                throw error
//            }
//        }
//
//        deinit {
//            opus_decoder_destroy(decoder)
//        }
//
//        public func reset() throws {
//            let error = Opus.Error(opus_decoder_init(decoder, Int32(format.sampleRate), Int32(format.channelCount)))
//            if error != .ok {
//                throw error
//            }
//        }
//    }
// }

// public extension Opus.RoamDecoder {
//    func decode(_ input: Data) throws -> AVAudioPCMBuffer {
//        try input.withUnsafeBytes {
//            let input = $0.bindMemory(to: UInt8.self)
//            let sampleCount = opus_decoder_get_nb_samples(decoder, input.baseAddress!, Int32($0.count))
//            if sampleCount < 0 {
//                throw Opus.Error(sampleCount)
//            }
//            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
//            try decode(input, to: output)
//            return output
//        }
//    }
//
//    func decode_loss_concealment(sampleCount: Int64) throws -> AVAudioPCMBuffer {
//        let input = UnsafeBufferPointer<UInt8>(start: nil, count: 0)
//
//        if sampleCount < 0 {
//            throw Opus.Error(sampleCount)
//        }
//        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
//        try decode(input, to: output)
//        return output
//    }
//
//    func decode(_ input: UnsafeBufferPointer<UInt8>, to output: AVAudioPCMBuffer) throws {
//        let decodedCount: Int
//        switch output.format.commonFormat {
//        case .pcmFormatInt16:
//            let output = UnsafeMutableBufferPointer(
//                start: output.int16ChannelData![0],
//                count: Int(output.frameCapacity)
//            )
//            decodedCount = try decode(input, to: output)
//        case .pcmFormatFloat32:
//            let output = UnsafeMutableBufferPointer(
//                start: output.floatChannelData![0],
//                count: Int(output.frameCapacity)
//            )
//            decodedCount = try decode(input, to: output)
//        default:
//            throw Opus.Error.badArgument
//        }
//        if decodedCount < 0 {
//            throw Opus.Error(decodedCount)
//        }
//        output.frameLength = AVAudioFrameCount(decodedCount)
//    }
// }
//
//// MARK: Private decode methods
//
// private extension Opus.RoamDecoder {
//    private func decode(_ input: UnsafeBufferPointer<UInt8>,
//                        to output: UnsafeMutableBufferPointer<Int16>) throws -> Int
//    {
//        let decodedCount = opus_decode(
//            decoder,
//            input.baseAddress,
//            Int32(input.count),
//            output.baseAddress!,
//            Int32(output.count),
//            0
//        )
//        if decodedCount < 0 {
//            throw Opus.Error(decodedCount)
//        }
//        return Int(decodedCount)
//    }
//
//    private func decode(_ input: UnsafeBufferPointer<UInt8>,
//                        to output: UnsafeMutableBufferPointer<Float32>) throws -> Int
//    {
//        let decodedCount = opus_decode_float(
//            decoder,
//            input.baseAddress,
//            Int32(input.count),
//            output.baseAddress!,
//            Int32(output.count),
//            0
//        )
//        if decodedCount < 0 {
//            throw Opus.Error(decodedCount)
//        }
//        return Int(decodedCount)
//    }
// }

extension AVAudioFormat {
    public enum OpusPCMFormat {
        case int16
        case float32
    }

    public convenience init?(opusPCMFormat: OpusPCMFormat, sampleRate: Double, channels: AVAudioChannelCount) {
        switch opusPCMFormat {
        case .int16:
            self.init(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: channels != 1)
        case .float32:
            self.init(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: channels != 1)
        }
        if !isValidOpusPCMFormat {
            return nil
        }
    }

    public var isValidOpusPCMFormat: Bool {
        switch sampleRate {
        case .opus8khz, .opus12khz, .opus16khz, .opus24khz, .opus48khz:
            break
        default:
            return false
        }

        switch channelCount {
        case 1, 2:
            break
        default:
            return false
        }

        if channelCount != 1, !isInterleaved {
            return false
        }

        if commonFormat == .pcmFormatInt16 || commonFormat == .pcmFormatFloat32 {
            return true
        }

        let desc = streamDescription.pointee
        if desc.mFormatID != kAudioFormatLinearPCM {
            return false
        }
        if desc.mFormatFlags & kLinearPCMFormatFlagIsSignedInteger != 0, desc.mBitsPerChannel != 16 {
            return false
        }
        if desc.mFormatFlags & kLinearPCMFormatFlagIsFloat != 0, desc.mBitsPerChannel != 32 {
            return false
        }

        return true
    }
}

extension Double {
    public static let opus8khz: Self = 8000
    public static let opus12khz: Self = 12000
    public static let opus16khz: Self = 16000
    public static let opus24khz: Self = 24000
    public static let opus48khz: Self = 48000
}
