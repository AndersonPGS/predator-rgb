import Foundation
import IOKit

/// Talks to PredatorWMI.kext (IOService "PredatorWMIBridge").
/// Protocol from acer-wmi / facer (Acer gaming WMI interface).
final class Keyboard {
    enum KBError: Error, LocalizedError {
        case driverNotLoaded, openFailed(kern_return_t), callFailed(UInt32, UInt64)
        var errorDescription: String? {
            switch self {
            case .driverNotLoaded: return "PredatorWMI driver is not loaded"
            case .openFailed(let kr): return String(format: "Could not open driver (0x%x)", kr)
            case .callFailed(let m, let r): return String(format: "WMI method %u failed (0x%llx)", m, r)
            }
        }
    }

    private var conn: io_connect_t = 0

    var isConnected: Bool { conn != 0 }

    func connect() throws {
        if conn != 0 { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("PredatorWMIBridge"))
        guard svc != 0 else { throw KBError.driverNotLoaded }
        defer { IOObjectRelease(svc) }
        var c: io_connect_t = 0
        let kr = IOServiceOpen(svc, mach_task_self_, 0, &c)
        guard kr == KERN_SUCCESS else { throw KBError.openFailed(kr) }
        conn = c
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    @discardableResult
    private func wmi(_ method: UInt32, _ input: [UInt8]) throws -> UInt64 {
        try connect()
        var scalarIn: UInt64 = UInt64(method)
        var out = [UInt64](repeating: 0, count: 3)
        var outCount: UInt32 = 3
        let kr = input.withUnsafeBytes { buf in
            IOConnectCallMethod(conn, 0, &scalarIn, 1, buf.baseAddress, buf.count,
                                &out, &outCount, nil, nil)
        }
        if kr != KERN_SUCCESS {
            // driver may have been reloaded: reconnect next time
            IOServiceClose(conn); conn = 0
            throw KBError.callFailed(method, UInt64(UInt32(bitPattern: kr)))
        }
        if out[2] != 0 { throw KBError.callFailed(method, out[2]) }
        return out[0]
    }

    private static func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xff) } }

    private func enableZones() throws {
        try wmi(2, Self.le64(8 | (15 << 40)))
    }

    private func setMode(mode: UInt8, speed: UInt8, brightness: UInt8, direction: UInt8,
                         r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0) throws {
        var p = [UInt8](repeating: 0, count: 16)
        p[0] = mode; p[1] = speed; p[2] = brightness; p[3] = mode == 3 ? 8 : 0
        p[4] = direction; p[5] = r; p[6] = g; p[7] = b; p[9] = 1
        try wmi(20, p)
    }

    /// colors: 4 zones, left to right.
    func setStatic(_ colors: [RGB], brightness: Int) throws {
        try enableZones()
        for (i, c) in colors.prefix(4).enumerated() {
            try wmi(6, [UInt8(1 << i), c.r, c.g, c.b, 0, 0, 0, 0])
        }
        try setMode(mode: 0, speed: 0, brightness: UInt8(clamping: brightness), direction: 0)
    }

    /// Fast path for app-driven animations: static mode must already be active.
    func setZonesOnly(_ colors: [RGB]) throws {
        for (i, c) in colors.prefix(4).enumerated() {
            try wmi(6, [UInt8(1 << i), c.r, c.g, c.b, 0, 0, 0, 0])
        }
    }

    func setZone(_ i: Int, _ c: RGB) throws {
        try wmi(6, [UInt8(1 << i), c.r, c.g, c.b, 0, 0, 0, 0])
    }

    func setEffect(_ effect: Effect, speed: Int, brightness: Int, direction: Int, color: RGB) throws {
        try enableZones()
        let c = effect.acceptsColor ? color : RGB(r: 0, g: 0, b: 0)
        try setMode(mode: effect.rawValue, speed: UInt8(clamping: speed),
                    brightness: UInt8(clamping: brightness), direction: UInt8(clamping: direction),
                    r: c.r, g: c.g, b: c.b)
    }

    func off() throws {
        try setMode(mode: 0, speed: 0, brightness: 0, direction: 0)
    }
}

struct RGB: Codable, Equatable {
    var r: UInt8, g: UInt8, b: UInt8
}

enum Effect: UInt8, CaseIterable, Codable, Identifiable {
    // Hardware effects supported by the keyboard firmware (same as PredatorSense).
    case breath = 1, neon = 2, wave = 3, shifting = 4, zoom = 5
    var id: UInt8 { rawValue }
    var name: String {
        switch self {
        case .breath: return "Breath"
        case .neon: return "Neon"
        case .wave: return "Wave"
        case .shifting: return "Shifting"
        case .zoom: return "Zoom"
        }
    }
    var acceptsColor: Bool { [.breath, .shifting, .zoom].contains(self) }
    var hasDirection: Bool { [.wave, .shifting, .zoom].contains(self) }
}
