import SwiftUI

@main
struct PredatorRGBApp: App {
    @StateObject private var controller = Controller()
    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(controller)
        } label: {
            Image(nsImage: MenuIcon.make(controller.iconColors))
        }
        .menuBarExtraStyle(.window)
    }
}

private let presets: [RGB] = [
    RGB(r: 255, g: 0, b: 0), RGB(r: 255, g: 96, b: 0), RGB(r: 255, g: 220, b: 0),
    RGB(r: 0, g: 255, b: 0), RGB(r: 0, g: 255, b: 220), RGB(r: 0, g: 80, b: 255),
    RGB(r: 160, g: 0, b: 255), RGB(r: 255, g: 0, b: 160), RGB(r: 255, g: 255, b: 255),
]

struct Swatches: View {
    @Binding var color: RGB
    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets.indices, id: \.self) { i in
                Circle().fill(presets[i].color).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.primary.opacity(presets[i] == color ? 0.9 : 0.15),
                                             lineWidth: presets[i] == color ? 2 : 1))
                    .onTapGesture { color = presets[i] }
            }
            ColorPicker("", selection: Binding(get: { color.color }, set: { color = RGB($0) }),
                        supportsOpacity: false).labelsHidden()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var c: Controller
    @State private var profileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $c.state.mode) {
                Text("Static").tag(LightMode.staticColor)
                Text("Built-in").tag(LightMode.effect)
                Text("Animated").tag(LightMode.animated)
                Text("Off").tag(LightMode.off)
            }
            .pickerStyle(.segmented).labelsHidden()

            if c.state.mode == .staticColor {
                Toggle("Same color on all zones", isOn: $c.state.linkZones)
                if c.state.linkZones {
                    Swatches(color: $c.state.zones[0])
                } else {
                    ForEach(0..<4, id: \.self) { i in
                        HStack { Text("Zone \(i + 1)").frame(width: 50, alignment: .leading)
                                 Swatches(color: $c.state.zones[i]) }
                    }
                }
            }

            if c.state.mode == .effect {
                Picker("Effect", selection: $c.state.effect) {
                    ForEach(Effect.allCases) { Text($0.name).tag($0) }
                }
                HStack { Text("Speed"); Slider(value: intBinding(\.speed), in: 1...9, step: 1)
                         Text("\(c.state.speed)").monospacedDigit().frame(width: 20) }
                if c.state.effect.hasDirection {
                    Picker("Direction", selection: $c.state.direction) {
                        Text("Right → Left").tag(1); Text("Left → Right").tag(2)
                    }.pickerStyle(.segmented)
                }
                if c.state.effect.acceptsColor { Swatches(color: $c.state.effectColor) }
            }

            if c.state.mode == .animated {
                Picker("Effect", selection: $c.state.softEffect) {
                    ForEach(SoftEffect.available) { Text($0.name).tag($0) }
                }
                if c.state.softEffect.usesSpeed {
                    HStack { Text("Speed"); Slider(value: intBinding(\.speed), in: 1...9, step: 1)
                             Text("\(c.state.speed)").monospacedDigit().frame(width: 20) }
                }
                if c.state.softEffect.usesPalette {
                    ForEach(c.state.palette.indices, id: \.self) { i in
                        HStack {
                            Swatches(color: $c.state.palette[i])
                            if c.state.palette.count > 1 {
                                Button { c.state.palette.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    if c.state.palette.count < 4 {
                        Button { c.state.palette.append(RGB(r: 255, g: 255, b: 255)) } label: {
                            Label("Add color", systemImage: "plus.circle") }.buttonStyle(.borderless)
                    }
                }
                if c.state.softEffect.isMusic {
                    Text("Reacts to any sound playing on the Mac. The first time, macOS asks to allow system audio recording; if the lights don't react, enable PredatorRGB in Privacy & Security > Screen & System Audio Recording.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !c.state.softEffect.slow && !c.state.softEffect.isMusic {
                    Picker("Smoothness", selection: $c.state.fps) {
                        Text("Light").tag(10); Text("Balanced").tag(20); Text("Smooth").tag(30)
                    }.pickerStyle(.segmented)
                }
                Text("Animated effects run while the app is open.").font(.caption).foregroundStyle(.secondary)
            }

            if c.state.mode != .off {
                HStack { Image(systemName: "sun.min"); Slider(value: intBinding(\.brightness), in: 0...100, step: 5)
                         Image(systemName: "sun.max") }
            }

            Divider()
            Text("Profiles").font(.caption).foregroundStyle(.secondary)
            ForEach(c.profiles) { p in
                HStack {
                    Button(p.name) { c.load(p) }.buttonStyle(.link)
                    Spacer()
                    Button { c.delete(p) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Profile name", text: $profileName).textFieldStyle(.roundedBorder)
                Button("Save") { c.saveProfile(named: profileName); profileName = "" }
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()
            if let e = c.lastError {
                Label(e, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
            Toggle("Show colors in menu bar icon", isOn: $c.liveIcon)
            Toggle("Launch at login", isOn: Binding(get: { c.launchAtLogin }, set: { c.setLaunchAtLogin($0) }))
            HStack {
                Button("Re-apply") { c.apply() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func intBinding(_ kp: WritableKeyPath<LightState, Int>) -> Binding<Double> {
        Binding(get: { Double(c.state[keyPath: kp]) }, set: { c.state[keyPath: kp] = Int($0) })
    }
}

/// Menu bar icon: the app logo as a compact glyph (keycap + sparkle).
/// Monochrome template by default; with live colors, the key's lit edge shows the 4 zone colors.
enum MenuIcon {
    static func make(_ colors: [RGB]) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let live = colors.count == 4
        let img = NSImage(size: size, flipped: false) { _ in
            let key = NSRect(x: 2, y: 1.5, width: 14, height: 13)
            let outer = NSBezierPath(roundedRect: key, xRadius: 3.2, yRadius: 3.2)
            let top = NSRect(x: 4, y: 4.5, width: 10, height: 8.5)
            let inner = NSBezierPath(roundedRect: top, xRadius: 2, yRadius: 2)
            // ring = outer minus top face
            let ring = NSBezierPath(); ring.append(outer); ring.append(inner.reversed)
            if live {
                NSGraphicsContext.saveGraphicsState()
                ring.addClip()
                for i in 0..<4 {
                    let c = colors[i]
                    NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1).setFill()
                    NSRect(x: key.minX + CGFloat(i) * key.width / 4, y: key.minY, width: key.width / 4 + 0.5, height: key.height).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
                NSColor.labelColor.withAlphaComponent(0.35).setStroke()
                outer.lineWidth = 0.5; outer.stroke()
            } else {
                NSColor.black.setFill(); ring.fill()
            }
            // sparkle on the key
            let c = NSPoint(x: top.midX, y: top.midY), r: CGFloat = 3.3
            let star = NSBezierPath()
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4 + .pi / 2
                let rad = i % 2 == 0 ? r : r * 0.3
                let p = NSPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
                i == 0 ? star.move(to: p) : star.line(to: p)
            }
            star.close()
            (live ? NSColor.labelColor : NSColor.black).setFill(); star.fill()
            return true
        }
        img.isTemplate = !live
        return img
    }
}
