import Foundation
import SwiftUI
import AppKit
import ServiceManagement

enum LightMode: String, Codable { case staticColor, effect, off }

struct LightState: Codable, Equatable {
    var mode: LightMode = .staticColor
    var zones: [RGB] = Array(repeating: RGB(r: 255, g: 0, b: 0), count: 4)
    var linkZones = true
    var brightness = 100
    var effect: Effect = .wave
    var speed = 4
    var direction = 1
    var effectColor = RGB(r: 255, g: 0, b: 0)
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
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private let kb = Keyboard()
    private var pending: DispatchWorkItem?

    init() {
        let d = UserDefaults.standard
        state = (d.data(forKey: "state")).flatMap { try? JSONDecoder().decode(LightState.self, from: $0) } ?? LightState()
        profiles = (d.data(forKey: "profiles")).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        // Re-apply after wake: the EC may reset the keyboard.
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

    func apply() {
        do {
            switch state.mode {
            case .staticColor:
                let z = state.linkZones ? Array(repeating: state.zones[0], count: 4) : state.zones
                try kb.setStatic(z, brightness: state.brightness)
            case .effect:
                try kb.setEffect(state.effect, speed: state.speed, brightness: state.brightness,
                                 direction: state.direction, color: state.effectColor)
            case .off:
                try kb.off()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
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
