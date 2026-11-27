import Foundation
import AppKit

/// Effects animated by the app (the firmware only has 5 built-in effects).
enum SoftEffect: String, CaseIterable, Codable, Identifiable {
    case rainbow, rainbowWave, colorCycle, breathing, strobe, police, cpuMeter, aurora
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
        }
    }
    /// Uses the palette colors chosen by the user.
    var usesPalette: Bool { [.colorCycle, .breathing, .strobe].contains(self) }
    var usesSpeed: Bool { self != .cpuMeter }
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
final class Animator {
    private let cpu = CPUSampler()
    private var cpuLevel = 0.0, lastCPU = -1.0

    func frame(_ e: SoftEffect, t: Double, speed: Int, palette: [RGB]) -> [RGB] {
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
            if t - lastCPU >= 0.5 { cpuLevel = cpuLevel * 0.5 + cpu.sample() * 0.5; lastCPU = t }
            // zones fill left to right; color goes green -> yellow -> red
            let color = rgb(HSV(h: 0.33 * (1 - cpuLevel), s: 1, v: 1))
            return (0..<4).map { z in
                let fill = min(max(cpuLevel * 4 - Double(z), 0), 1)
                return scale(color, 0.08 + 0.92 * fill)
            }
        case .aurora:
            return (0..<4).map { z in
                let h = 0.38 + 0.18 * sin(t * sp * 1.3 + Double(z) * 0.9)
                let v = 0.55 + 0.45 * sin(t * sp * 2.1 + Double(z) * 1.7)
                return rgb(HSV(h: h, s: 0.9, v: v))
            }
        }
    }
}
