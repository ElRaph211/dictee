import Foundation
import AVFoundation
import CoreAudio

/// Enregistreur micro : AVAudioEngine → PCM float32 mono 16 kHz, avec niveau audio pour la pastille.
final class Recorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false
    var onLevel: ((Float) -> Void)?
    var maxSeconds: Double = 120

    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    /// Micros disponibles (nom → deviceID), pour le menu.
    static func inputDevices() -> [(name: String, id: AudioDeviceID)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        var out: [(String, AudioDeviceID)] = []
        for id in ids {
            var inputAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                       mScope: kAudioDevicePropertyScopeInput,
                                                       mElement: kAudioObjectPropertyElementMain)
            var cfgSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &inputAddr, 0, nil, &cfgSize) == noErr, cfgSize > 0 else { continue }
            let bufList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(cfgSize))
            defer { bufList.deallocate() }
            guard AudioObjectGetPropertyData(id, &inputAddr, 0, nil, &cfgSize, bufList) == noErr else { continue }
            let channels = UnsafeMutableAudioBufferListPointer(bufList).reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0 else { continue }
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                      mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name) == noErr, let cf = name?.takeRetainedValue() else { continue }
            out.append((cf as String, id))
        }
        return out
    }

    /// Choisit le micro par son nom (sinon micro par défaut du système).
    func start(micName: String?) throws {
        stopInternal()
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        if let micName = micName,
           let device = Self.inputDevices().first(where: { $0.name == micName }) {
            var id = device.id
            if let unit = engine.inputNode.audioUnit {
                AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                     kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            }
        }
        let input = engine.inputNode
        let srcFormat = input.inputFormat(forBus: 0)
        guard srcFormat.sampleRate > 0 else {
            throw NSError(domain: "Dictee", code: 10, userInfo: [NSLocalizedDescriptionKey: "Micro indisponible (autorisation ou périphérique)"])
        }
        converter = AVAudioConverter(from: srcFormat, to: Self.targetFormat)
        let maxSamples = Int(maxSeconds * 16000)
        input.installTap(onBus: 0, bufferSize: 4096, format: srcFormat) { [weak self] buffer, _ in
            guard let self = self, let conv = self.converter else { return }
            let ratio = 16000.0 / srcFormat.sampleRate
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: cap) else { return }
            var fed = false
            conv.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            guard let ch = out.floatChannelData, out.frameLength > 0 else { return }
            let chunk = UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength))
            var level: Float = 0
            for v in chunk { level = max(level, abs(v)) }
            self.lock.lock()
            if self.samples.count < maxSamples { self.samples.append(contentsOf: chunk) }
            self.lock.unlock()
            self.onLevel?(min(1, level * 1.6))
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Arrête et rend l'audio (PCM 16 kHz mono).
    func stop() -> [Float] {
        stopInternal()
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    func cancel() { stopInternal(); lock.lock(); samples.removeAll(); lock.unlock() }

    private func stopInternal() {
        guard isRecording || engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
    }
}
