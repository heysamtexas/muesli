// Minimal system audio capture using Core Audio Taps API (macOS 14.2+)
// Writes raw PCM (16-bit signed LE, 16kHz mono) to stdout or to a file.
// Usage: system_audio [output.wav] [--duration N]
//   No args: writes raw PCM to stdout until interrupted
//   output.wav: writes WAV file until interrupted or --duration reached

import Foundation
import CoreAudio
import AudioToolbox

// MARK: - WAV Header

struct WAVHeader {
    static func create(sampleRate: Int, channels: Int, bitsPerSample: Int, dataSize: Int) -> Data {
        var header = Data()
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        return header
    }
}

// MARK: - Globals

let sampleRate: Float64 = 16000
let channels: UInt32 = 1
var outputFile: FileHandle? = nil
var outputPath: String? = nil
var maxDuration: Double = 0 // 0 = unlimited
var totalBytesWritten: Int = 0
var startTime: Date? = nil
var isRunning = true

// MARK: - Audio Tap Callback

let tapCallback: AudioDeviceIOProc = { (device, now, inputData, inputTime, outputData, outputTime, clientData) -> OSStatus in
    guard let bufferList = inputData?.pointee else { return noErr }

    for i in 0..<Int(bufferList.mNumberBuffers) {
        let buffer = bufferList.mBuffers // For single buffer access
        if let data = buffer.mData {
            let byteCount = Int(buffer.mDataByteSize)
            let rawData = Data(bytes: data, count: byteCount)

            if let file = outputFile {
                file.write(rawData)
            } else {
                FileHandle.standardOutput.write(rawData)
            }
            totalBytesWritten += byteCount
        }
    }

    if maxDuration > 0, let start = startTime {
        if Date().timeIntervalSince(start) >= maxDuration {
            isRunning = false
        }
    }

    return noErr
}

// MARK: - Main

func main() {
    let args = CommandLine.arguments

    // Parse arguments
    var i = 1
    while i < args.count {
        if args[i] == "--duration" && i + 1 < args.count {
            maxDuration = Double(args[i + 1]) ?? 0
            i += 2
        } else {
            outputPath = args[i]
            i += 1
        }
    }

    // Set up output file if path specified
    if let path = outputPath {
        FileManager.default.createFile(atPath: path, contents: nil)
        outputFile = FileHandle(forWritingAtPath: path)
        // Write placeholder WAV header (will update at end)
        let header = WAVHeader.create(sampleRate: Int(sampleRate), channels: Int(channels), bitsPerSample: 16, dataSize: 0)
        outputFile?.write(header)
    }

    // Get default output device
    var deviceID: AudioDeviceID = 0
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0, nil,
        &propertySize,
        &deviceID
    )

    guard status == noErr else {
        fputs("Error: Could not get default output device (status: \(status))\n", stderr)
        exit(1)
    }

    fputs("Capturing system audio from device \(deviceID)...\n", stderr)

    // Create process tap description
    var tapDescription = CATapDescription(stereoMixdownOfProcesses: [])
    tapDescription.uuid = UUID()
    tapDescription.name = "MuesliSystemAudio" as CFString

    // Set desired format: 16kHz mono 16-bit signed integer
    var desiredFormat = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2 * channels,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2 * channels,
        mChannelsPerFrame: channels,
        mBitsPerChannel: 16,
        mReserved: 0
    )

    // Create the tap
    var tapID: AudioObjectID = 0
    var createStatus = AudioHardwareCreateProcessTap(&tapDescription, &tapID)

    guard createStatus == noErr else {
        fputs("Error: Could not create process tap (status: \(createStatus))\n", stderr)
        fputs("Make sure you have granted Screen Recording / Audio Capture permission.\n", stderr)
        exit(1)
    }

    // Create aggregate device with the tap
    var aggDesc: CFDictionary = [
        kAudioAggregateDeviceNameKey: "MuesliCapture",
        kAudioAggregateDeviceUIDKey: "com.muesli.capture.\(UUID().uuidString)",
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [[
            kAudioSubTapUIDKey: tapDescription.uuid.uuidString
        ]],
        kAudioAggregateDeviceMainSubDeviceKey: tapDescription.uuid.uuidString
    ] as CFDictionary

    var aggDevice: AudioDeviceID = 0
    createStatus = AudioHardwareCreateAggregateDevice(aggDesc, &aggDevice)

    guard createStatus == noErr else {
        fputs("Error: Could not create aggregate device (status: \(createStatus))\n", stderr)
        AudioHardwareDestroyProcessTap(tapID)
        exit(1)
    }

    // Set the stream format on the aggregate device
    var formatAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamFormat,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: 0
    )
    var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    AudioObjectSetPropertyData(aggDevice, &formatAddress, 0, nil, formatSize, &desiredFormat)

    // Add IO proc
    var procID: AudioDeviceIOProcID? = nil
    AudioDeviceCreateIOProcID(aggDevice, tapCallback, nil, &procID)

    startTime = Date()
    AudioDeviceStart(aggDevice, procID)

    fputs("Recording... Press Ctrl+C to stop.\n", stderr)

    // Handle SIGINT for clean shutdown
    signal(SIGINT) { _ in isRunning = false }
    signal(SIGTERM) { _ in isRunning = false }

    // Run until stopped
    while isRunning {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }

    // Cleanup
    AudioDeviceStop(aggDevice, procID)
    if let procID = procID {
        AudioDeviceDestroyIOProcID(aggDevice, procID)
    }
    AudioHardwareDestroyAggregateDevice(aggDevice)
    AudioHardwareDestroyProcessTap(tapID)

    // Update WAV header with actual size
    if let file = outputFile, outputPath != nil {
        let header = WAVHeader.create(sampleRate: Int(sampleRate), channels: Int(channels), bitsPerSample: 16, dataSize: totalBytesWritten)
        file.seek(toFileOffset: 0)
        file.write(header)
        file.closeFile()
        fputs("Wrote \(totalBytesWritten) bytes to \(outputPath!)\n", stderr)
    }

    fputs("Done.\n", stderr)
}

main()
