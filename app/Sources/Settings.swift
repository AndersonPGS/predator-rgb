import Foundation
import SwiftUI
import AppKit
import ServiceManagement

enum LightMode: String, Codable { case staticColor, effect, animated, off }

struct LightState: Codable, Equatable {
    var mode: LightMode = .staticColor
    var zones: [RGB] = Array(repeating: RGB(r: 255, g: 0, b: 0), count: 4)
    var linkZones = true
    var brightness = 100
    var effect: Effect = .wave
    var speed = 4
    var direction = 1
    var effectColor = RGB(r: 255, g: 0, b: 0)
    var softEffect: SoftEffect = .rainbowWave
    var palette: [RGB] = [RGB(r: 255, g: 0, b: 0), RGB(r: 0, g: 80, b: 255), RGB(r: 160, g: 0, b: 255)]
    var fps = 20

    init() {}
    // Tolerant decoding: unknown/missing fields fall back to defaults.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = LightState()
        mode = (try? c.decode(LightMode.self, forKey: .mode)) ?? def.mode
        zones = (try? c.decode([RGB].self, forKey: .zones)) ?? def.zones
        linkZones = (try? c.decode(Bool.self, forKey: .linkZones)) ?? def.linkZones
        brightness = (try? c.decode(Int.self, forKey: .brightness)) ?? def.brightness
        effect = (try? c.decode(Effect.self, forKey: .effect)) ?? def.effect
        speed = (try? c.decode(Int.self, forKey: .speed)) ?? def.speed
        direction = (try? c.decode(Int.self, forKey: .direction)) ?? def.direction
        effectColor = (try? c.decode(RGB.self, forKey: .effectColor)) ?? def.effectColor
        softEffect = (try? c.decode(SoftEffect.self, forKey: .softEffect)) ?? def.softEffect
        palette = (try? c.decode([RGB].self, forKey: .palette)) ?? def.palette
        fps = (try? c.decode(Int.self, forKey: .fps)) ?? def.fps
    }
}

struct Profile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var state: LightState
}

@MainActor
final class Controller: ObservableObject {
    @Published var state: LightState { didSet { if state != oldValue { save(); scheduleApply() } } }
    @Published var profiles: [Profile] { didSet { saveProfiles() } }
    @Published var lastError: String?
    @Published var liveIcon: Bool = UserDefaults.standard.object(forKey: "liveIcon") as? Bool ?? false {
        didSet { UserDefaults.standard.set(liveIcon, forKey: "liveIcon"); refreshIcon() }
    }
    /// Colors drawn in the menu bar icon. Empty = monochrome outline.
    @Published var iconColors: [RGB] = []
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    /// Colors shown in the menu bar icon (approximate for hardware effects).
    @Published var preview: [RGB] = []

    private let kb = Keyboard()
    private var pending: DispatchWorkItem?
    private var timer: Timer?
    private let animator = Animator()
    private var animStart = Date()
    private var frameCount = 0
    private var lastSent: [RGB] = []
    private var audioTap: AnyObject?

    private var audioBands: [Float] {
        if #available(macOS 14.2, *), let tap = audioTap as? AudioTap { return tap.bands() }
        return [0, 0, 0, 0]
    }

    /// Starts system-audio capture only for music effects (permission is requested on first use).
    private func updateAudio() {
        guard #available(macOS 14.2, *) else { return }
        let want = state.mode == .animated && state.softEffect.isMusic
        if want {
            let tap = (audioTap as? AudioTap) ?? AudioTap()
            audioTap = tap
            do { try tap.start() } catch { lastError = error.localizedDescription }
        } else if let tap = audioTap as? AudioTap {
            tap.stop(); audioTap = nil
        }
    }

    init() {
        let d = UserDefaults.standard
        state = (d.data(forKey: "state")).flatMap { try? JSONDecoder().decode(LightState.self, from: $0) } ?? LightState()
        profiles = (d.data(forKey: "profiles")).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        // Re-apply after wake: the EC may reset the keyboard.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.stopAnimation()
                if #available(macOS 14.2, *), let tap = self?.audioTap as? AudioTap { tap.stop() }
                self?.audioTap = nil
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Task { @MainActor in self?.apply() } }
        }
        applyWithRetry(attempts: 10)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "state") }
    }
    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "profiles") }
    }

    private func scheduleApply() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in Task { @MainActor in self?.apply() } }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    private func applyWithRetry(attempts: Int) {
        apply()
        if lastError != nil && attempts > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                Task { @MainActor in self?.applyWithRetry(attempts: attempts - 1) }
            }
        }
    }

    private func stopAnimation() { timer?.invalidate(); timer = nil }

    private func startAnimation() throws {
        stopAnimation()
        let first = animator.frame(state.softEffect, t: 0, speed: state.speed, palette: state.palette)
        try kb.setStatic(first, brightness: state.brightness)
        lastSent = first
        animStart = Date()
        let rate = state.softEffect.slow ? 2.0 : state.softEffect.isMusic ? 30.0 : Double(max(5, min(state.fps, 30)))
        let t = Timer(timeInterval: 1.0 / rate, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let t = Date().timeIntervalSince(animStart)
        let colors = animator.frame(state.softEffect, t: t, speed: state.speed, palette: state.palette, audio: audioBands)
        // Only send zones that changed: fewer ACPI/EC calls.
        do {
            for z in 0..<4 where lastSent.count != 4 || colors[z] != lastSent[z] {
                try kb.setZone(z, colors[z])
            }
            lastSent = colors
        } catch { lastError = error.localizedDescription; stopAnimation(); return }
        frameCount += 1
        if liveIcon && frameCount % 10 == 0 { preview = colors; refreshIcon() }
    }

    func apply() {
        stopAnimation()
        updateAudio()
        do {
            switch state.mode {
            case .animated:
                try startAnimation()
                preview = lastSent
                refreshIcon()
                lastError = nil
                return
            case .staticColor:
                let z = state.linkZones ? Array(repeating: state.zones[0], count: 4) : state.zones
                try kb.setStatic(z, brightness: state.brightness)
                preview = z
                refreshIcon()
            case .effect:
                preview = state.effect.acceptsColor ? Array(repeating: state.effectColor, count: 4)
                    : [RGB(r: 255, g: 0, b: 0), RGB(r: 0, g: 255, b: 0), RGB(r: 0, g: 80, b: 255), RGB(r: 160, g: 0, b: 255)]
                refreshIcon()
                try kb.setEffect(state.effect, speed: state.speed, brightness: state.brightness,
                                 direction: state.direction, color: state.effectColor)
            case .off:
                try kb.off()
                preview = []
                refreshIcon()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Live icon: zone colors. Otherwise a monochrome icon that never changes while animating.
    private func refreshIcon() {
        let target = liveIcon ? preview : []
        if target != iconColors { iconColors = target }
    }

    func saveProfile(named name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let i = profiles.firstIndex(where: { $0.name == n }) { profiles[i].state = state }
        else { profiles.append(Profile(name: n, state: state)) }
    }

    func load(_ p: Profile) { state = p.state }
    func delete(_ p: Profile) { profiles.removeAll { $0.id == p.id } }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { lastError = "Launch at login: \(error.localizedDescription)" }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    init(_ c: Color) {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .red
        r = UInt8(clamping: Int((n.redComponent * 255).rounded()))
        g = UInt8(clamping: Int((n.greenComponent * 255).rounded()))
        b = UInt8(clamping: Int((n.blueComponent * 255).rounded()))
    }
}
