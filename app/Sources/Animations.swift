import Foundation
import AppKit
import IOKit.ps

/// Effects animated by the app (the firmware only has 5 built-in effects).
enum SoftEffect: String, CaseIterable, Codable, Identifiable {
    case rainbow, rainbowWave, colorCycle, breathing, strobe, police, cpuMeter, aurora
    case fire, candle, ocean, sunset, lava, heartbeat, scanner, sparkle, pingPong, batteryMeter, clock
    case musicSpectrum, musicPulse, musicRainbow, musicVU

    var isMusic: Bool { [.musicSpectrum, .musicPulse, .musicRainbow, .musicVU].contains(self) }
    static var available: [SoftEffect] {
        if #available(macOS 14.2, *) { return allCases }
        return allCases.filter { !$0.isMusic }
    }
    var id: String { rawValue }
    var name: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .rainbowWave: return "Rainbow wave"
        case .colorCycle: return "Color cycle"
        case .breathing: return "Breathing (multi-color)"
        case .strobe: return "Strobe"
        case .police: return "Police"
        case .cpuMeter: return "CPU load meter"
        case .aurora: return "Aurora"
        case .fire: return "Fire"
        case .candle: return "Candle"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .lava: return "Lava lamp"
        case .heartbeat: return "Heartbeat"
        case .scanner: return "Scanner"
        case .sparkle: return "Sparkle"
        case .pingPong: return "Ping-pong"
        case .batteryMeter: return "Battery meter"
        case .clock: return "Time of day"
        case .musicSpectrum: return "Music: spectrum"
        case .musicPulse: return "Music: bass pulse"
        case .musicRainbow: return "Music: rainbow beat"
        case .musicVU: return "Music: VU meter"
        }
    }
    /// Uses the palette colors chosen by the user.
    var usesPalette: Bool { [.colorCycle, .breathing, .strobe, .heartbeat, .scanner, .sparkle, .pingPong, .musicPulse].contains(self) }
    var usesSpeed: Bool { ![.cpuMeter, .batteryMeter, .clock, .musicSpectrum, .musicPulse, .musicVU].contains(self) }
    /// Effects that change slowly can run at a low frame rate.
    var slow: Bool { [.cpuMeter, .batteryMeter, .clock].contains(self) }
    /// Seconds between updates for slow effects (colors are only sent when they change).
    var updateInterval: Double {
        switch self {
        case .clock: return 30
        case .batteryMeter: return 5
        default: return 0.5
        }
    }
}

struct HSV { var h, s, v: Double }

func rgb(_ c: HSV) -> RGB {
    let n = NSColor(hue: CGFloat(c.h.truncatingRemainder(dividingBy: 1) + (c.h < 0 ? 1 : 0)),
                    saturation: CGFloat(c.s), brightness: CGFloat(c.v), alpha: 1)
    return RGB(r: UInt8(clamping: Int(n.redComponent * 255)), g: UInt8(clamping: Int(n.greenComponent * 255)),
               b: UInt8(clamping: Int(n.blueComponent * 255)))
}

func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(clamping: Int(Double(x) + (Double(y) - Double(x)) * t)) }
    return RGB(r: m(a.r, b.r), g: m(a.g, b.g), b: m(a.b, b.b))
}

func scale(_ c: RGB, _ k: Double) -> RGB {
    RGB(r: UInt8(clamping: Int(Double(c.r) * k)), g: UInt8(clamping: Int(Double(c.g) * k)), b: UInt8(clamping: Int(Double(c.b) * k)))
}

/// CPU usage 0...1 since the previous call.
final class CPUSampler {
    private var prev: (busy: UInt64, total: UInt64)?
    func sample() -> Double {
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        var cpus: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpus, &info, &count) == KERN_SUCCESS,
              let info else { return 0 }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(cpus) {
            let b = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[b + Int(CPU_STATE_USER)]), sys = UInt64(info[b + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[b + Int(CPU_STATE_NICE)]), idle = UInt64(info[b + Int(CPU_STATE_IDLE)])
            busy += user + sys + nice; total += user + sys + nice + idle
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        defer { prev = (busy, total) }
        guard let p = prev, total > p.total else { return 0 }
        return Double(busy - p.busy) / Double(total - p.total)
    }
}

/// Produces the 4 zone colors for time t (seconds).
private func battery() -> (level: Double, charging: Bool) {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (1, true) }
    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
              let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
        return (Double(cur) / Double(max), (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
    }
    return (1, true)
}

/// Smooth pseudo-random noise in 0...1.
private func noise(_ x: Double, _ seed: Double) -> Double {
    func h(_ n: Double) -> Double { let v = sin(n * 127.1 + seed * 311.7) * 43758.5453; return v - floor(v) }
    let i = floor(x), f = x - i, u = f * f * (3 - 2 * f)
    return h(i) * (1 - u) + h(i + 1) * u
}

final class Animator {
    private let cpu = CPUSampler()
    private var cpuLevel = 0.0, lastCPU = -1.0
    private var batt = (level: 1.0, charging: true), lastBatt = -100.0
    private var sparks = [Double](repeating: 0, count: 4), sparkColor = [Int](repeating: 0, count: 4), lastT = 0.0

    private var beatHue = 0.0, prevBass: Float = 0

    func frame(_ e: SoftEffect, t: Double, speed: Int, palette: [RGB], audio: [Float] = [0, 0, 0, 0]) -> [RGB] {
        let sp = 0.08 * Double(speed)                     // cycles per second
        let pal = palette.isEmpty ? [RGB(r: 255, g: 0, b: 0)] : palette
        switch e {
        case .rainbow:
            return Array(repeating: rgb(HSV(h: t * sp, s: 1, v: 1)), count: 4)
        case .rainbowWave:
            return (0..<4).map { rgb(HSV(h: t * sp + Double($0) * 0.12, s: 1, v: 1)) }
        case .colorCycle:
            let x = t * sp * Double(pal.count)
            let i = Int(x) % pal.count, f = x - floor(x)
            return Array(repeating: mix(pal[i], pal[(i + 1) % pal.count], f), count: 4)
        case .breathing:
            let x = t * sp
            let i = Int(x) % pal.count
            let k = 0.5 - 0.5 * cos(2 * .pi * (x - floor(x)))
            return Array(repeating: scale(pal[i], k), count: 4)
        case .strobe:
            let x = t * sp * 6
            let on = x - floor(x) < 0.5
            let c = pal[Int(x) % pal.count]
            return Array(repeating: on ? c : RGB(r: 0, g: 0, b: 0), count: 4)
        case .police:
            let x = t * sp * 4
            let phase = Int(x) % 2, flash = (x - floor(x)) < 0.5
            let red = RGB(r: 255, g: 0, b: 0), blue = RGB(r: 0, g: 40, b: 255), off = RGB(r: 0, g: 0, b: 0)
            return phase == 0 ? [flash ? red : off, flash ? red : off, off, off]
                              : [off, off, flash ? blue : off, flash ? blue : off]
        case .cpuMeter:
            if t - lastCPU >= 0.45 { cpuLevel = cpuLevel * 0.5 + cpu.sample() * 0.5; lastCPU = t }
            // zones fill left to right; color goes green -> yellow -> red
            let color = rgb(HSV(h: 0.33 * (1 - cpuLevel), s: 1, v: 1))
            return (0..<4).map { z in
                let fill = min(max(cpuLevel * 4 - Double(z), 0), 1)
                return scale(color, 0.08 + 0.92 * fill)
            }
        case .fire:
            return (0..<4).map { z in
                let n = noise(t * (2 + sp * 6), Double(z) * 3.3)
                return rgb(HSV(h: 0.015 + 0.075 * n, s: 1, v: 0.45 + 0.55 * n))
            }
        case .candle:
            let n = noise(t * (1.5 + sp * 4), 7)
            return (0..<4).map { z in rgb(HSV(h: 0.07, s: 0.85, v: 0.35 + 0.65 * (0.7 * n + 0.3 * noise(t * 3, Double(z))))) }
        case .ocean:
            return (0..<4).map { z in
                let w = 0.5 + 0.5 * sin(t * sp * 2 - Double(z) * 0.8)
                return rgb(HSV(h: 0.5 + 0.12 * w, s: 0.95, v: 0.4 + 0.6 * w))
            }
        case .sunset:
            return (0..<4).map { z in
                let w = 0.5 + 0.5 * sin(t * sp * 0.8 + Double(z) * 0.5)
                return rgb(HSV(h: 0.95 + 0.13 * w, s: 0.9, v: 0.65 + 0.35 * w))
            }
        case .lava:
            return (0..<4).map { z in
                let n = noise(t * (0.3 + sp), Double(z) * 1.9)
                return rgb(HSV(h: 0.92 + 0.12 * n, s: 1, v: 0.5 + 0.5 * n))
            }
        case .heartbeat:
            let x = (t * (0.5 + sp)).truncatingRemainder(dividingBy: 1)
            func pulse(_ c: Double) -> Double { max(0, 1 - abs(x - c) / 0.07) }
            let k = 0.06 + 0.94 * max(pulse(0.1), 0.75 * pulse(0.3))
            return Array(repeating: scale(pal[0], k), count: 4)
        case .scanner, .pingPong:
            let x = t * sp * 3
            let pos = 1.5 + 1.5 * sin(x * .pi)           // bounces between zone 0 and 3
            let c = pal[(Int(x / 2) % pal.count)]
            return (0..<4).map { z in
                let d = abs(Double(z) - pos)
                return e == .scanner ? scale(c, max(0.03, 1 - d * 0.75)) : (d < 0.5 ? c : RGB(r: 0, g: 0, b: 0))
            }
        case .sparkle:
            let dt = max(0, min(t - lastT, 0.2)); lastT = t
            var out = [RGB]()
            for z in 0..<4 {
                sparks[z] = max(0, sparks[z] - dt * (1 + sp * 4))
                if sparks[z] == 0 && Double.random(in: 0...1) < dt * (0.6 + sp * 3) {
                    sparks[z] = 1; sparkColor[z] = Int.random(in: 0..<pal.count)
                }
                out.append(scale(pal[sparkColor[z] % pal.count], sparks[z] * sparks[z]))
            }
            return out
        case .batteryMeter:
            if t - lastBatt >= 4.9 { batt = battery(); lastBatt = t }
            let color = batt.charging ? RGB(r: 0, g: 140, b: 255) : rgb(HSV(h: 0.33 * batt.level, s: 1, v: 1))
            return (0..<4).map { z in scale(color, 0.06 + 0.94 * min(max(batt.level * 4 - Double(z), 0), 1)) }
        case .clock:
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
            // night deep blue -> morning orange -> day white-ish -> evening red -> night
            let stops: [(Double, RGB)] = [(0, RGB(r: 20, g: 0, b: 120)), (6, RGB(r: 255, g: 90, b: 20)),
                                          (9, RGB(r: 255, g: 200, b: 120)), (13, RGB(r: 200, g: 230, b: 255)),
                                          (18, RGB(r: 255, g: 60, b: 20)), (21, RGB(r: 90, g: 0, b: 160)), (24, RGB(r: 20, g: 0, b: 120))]
            var col = stops[0].1
            for i in 0..<(stops.count - 1) where h >= stops[i].0 && h <= stops[i + 1].0 {
                col = mix(stops[i].1, stops[i + 1].1, (h - stops[i].0) / (stops[i + 1].0 - stops[i].0))
            }
            return Array(repeating: col, count: 4)
        case .musicSpectrum:
            let hues = [0.0, 0.12, 0.45, 0.72]
            return (0..<4).map { z in rgb(HSV(h: hues[z], s: 1, v: Double(max(0.04, audio[z])))) }
        case .musicPulse:
            let k = Double(max(0.05, audio[0] * audio[0]))
            return Array(repeating: scale(pal[0], k), count: 4)
        case .musicRainbow:
            if audio[0] > 0.8 && prevBass <= 0.8 { beatHue += 0.17 }
            prevBass = audio[0]
            beatHue += 0.002 * Double(speed)
            let k = 0.25 + 0.75 * Double(audio[0])
            return (0..<4).map { z in rgb(HSV(h: beatHue + Double(z) * 0.08, s: 1, v: k)) }
        case .musicVU:
            let level = Double(audio.reduce(0, +) / 4)
            let color = rgb(HSV(h: 0.33 * (1 - min(level * 1.2, 1)), s: 1, v: 1))
            return (0..<4).map { z in scale(color, 0.04 + 0.96 * min(max(level * 4.5 - Double(z), 0), 1)) }
        case .aurora:
            return (0..<4).map { z in
                let h = 0.38 + 0.18 * sin(t * sp * 1.3 + Double(z) * 0.9)
                let v = 0.55 + 0.45 * sin(t * sp * 2.1 + Double(z) * 1.7)
                return rgb(HSV(h: h, s: 0.9, v: v))
            }
        }
    }
}
