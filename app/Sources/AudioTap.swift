import Foundation
import CoreAudio
import AudioToolbox
import Accelerate

/// Captures system audio output with a Core Audio process tap (macOS 14.2+) and
/// exposes 4 frequency band levels (0...1), left to right: bass, low-mid, high-mid, treble.
/// macOS asks for "System Audio Recording" permission the first time start() runs,
/// so the prompt only appears when the user picks a music effect.
@available(macOS 14.2, *)
final class AudioTap {
    enum TapError: Error, LocalizedError {
        case tap(OSStatus), device(OSStatus), io(OSStatus)
        var errorDescription: String? {
            switch self {
            case .tap(let e): return String(format: NSLocalizedString("Could not capture system audio (%d)", comment: ""), Int(e))
            case .device(let e): return String(format: NSLocalizedString("Could not create audio device (%d)", comment: ""), Int(e))
            case .io(let e): return String(format: NSLocalizedString("Could not start audio (%d)", comment: ""), Int(e))
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "PredatorRGB.audio")
    private let lock = NSLock()
    private var levels = [Float](repeating: 0, count: 4)
    private var peaks = [Float](repeating: 1e-4, count: 4)
    private var sampleRate: Double = 48000

    // FFT
    private let n = 1024
    private lazy var log2n = vDSP_Length(log2(Double(n)))
    private lazy var fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    private lazy var window: [Float] = { var w = [Float](repeating: 0, count: n); vDSP_hann_window(&w, vDSP_Length(n), Int32(vDSP_HANN_NORM)); return w }()
    private var ring = [Float]()

    var isRunning: Bool { procID != nil }

    func bands() -> [Float] { lock.lock(); defer { lock.unlock() }; return levels }

    func start() throws {
        if isRunning { return }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var tid = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateProcessTap(desc, &tid)
        guard err == noErr else { throw TapError.tap(err) }
        tapID = tid

        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(tid, &addr, 0, nil, &size, &asbd) == noErr, asbd.mSampleRate > 0 {
            sampleRate = asbd.mSampleRate
        }

        let outUID = Self.defaultOutputUID() ?? ""
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PredatorRGB Audio Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                              kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var aid = AudioObjectID(kAudioObjectUnknown)
        err = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aid)
        guard err == noErr else { stop(); throw TapError.device(err) }
        aggID = aid

        var pid: AudioDeviceIOProcID?
        err = AudioDeviceCreateIOProcIDWithBlock(&pid, aid, queue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }
        guard err == noErr, let pid else { stop(); throw TapError.io(err) }
        procID = pid
        err = AudioDeviceStart(aid, pid)
        guard err == noErr else { stop(); throw TapError.io(err) }
    }

    func stop() {
        if let p = procID, aggID != kAudioObjectUnknown {
            AudioDeviceStop(aggID, p)
            AudioDeviceDestroyIOProcID(aggID, p)
        }
        procID = nil
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
        lock.lock(); levels = [0, 0, 0, 0]; lock.unlock()
        queue.async { [weak self] in self?.ring.removeAll() }
    }

    deinit { stop() }

    private static func defaultOutputUID() -> String? {
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    /// Mixes the (float, interleaved or not) buffers to mono and runs the analysis.
    private func process(_ list: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = abl.first, let data = first.mData else { return }
        let ch = max(Int(first.mNumberChannels), 1)
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / ch
        let p = data.assumingMemoryBound(to: Float.self)
        for f in 0..<frames {
            var s: Float = 0
            for c in 0..<ch { s += p[f * ch + c] }
            ring.append(s / Float(ch))
        }
        while ring.count >= n {
            analyze(Array(ring.prefix(n)))
            ring.removeFirst(n / 2)
        }
    }

    private func analyze(_ samples: [Float]) {
        var x = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &x, 1, vDSP_Length(n))
        var re = [Float](repeating: 0, count: n / 2), im = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        let binHz = sampleRate / Double(n)
        let edges: [Double] = [30, 160, 600, 2500, 10000]
        var out = [Float](repeating: 0, count: 4)
        for b in 0..<4 {
            let lo = max(1, Int(edges[b] / binHz)), hi = min(n / 2 - 1, max(lo + 1, Int(edges[b + 1] / binHz)))
            var sum: Float = 0
            vDSP_meanv(Array(mags[lo..<hi]), 1, &sum, vDSP_Length(hi - lo))
            out[b] = sum
        }
        lock.lock()
        for b in 0..<4 {
            // automatic gain: slowly decaying peak per band
            peaks[b] = max(out[b], peaks[b] * 0.995, 1e-4)
            let v = min(out[b] / peaks[b], 1)
            // fast attack, slower release
            levels[b] = v > levels[b] ? v : levels[b] * 0.82 + v * 0.18
        }
        lock.unlock()
    }
}
