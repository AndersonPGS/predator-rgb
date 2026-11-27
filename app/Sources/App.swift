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

/// Menu bar icon: the logo as a glyph — thin keycap outline with a large sparkle filling it.
/// Monochrome template by default; with live colors, the outline shows the 4 zone colors.
enum MenuIcon {
    static func make(_ colors: [RGB]) -> NSImage {
        let size = NSSize(width: 17, height: 16)
        let live = colors.count == 4
        let img = NSImage(size: size, flipped: false) { _ in
            let key = NSRect(x: 1.5, y: 1.5, width: 14, height: 13)
            let outline = NSBezierPath(roundedRect: key, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1.3
            if live {
                NSGraphicsContext.saveGraphicsState()
                let stroked = NSBezierPath(roundedRect: key.insetBy(dx: -0.65, dy: -0.65), xRadius: 4, yRadius: 4)
                stroked.append(NSBezierPath(roundedRect: key.insetBy(dx: 0.65, dy: 0.65), xRadius: 3, yRadius: 3).reversed)
                stroked.addClip()
                for i in 0..<4 {
                    let c = colors[i]
                    NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1).setFill()
                    NSRect(x: CGFloat(i) * size.width / 4, y: 0, width: size.width / 4 + 0.5, height: size.height).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.black.setStroke(); outline.stroke()
            }
            // big 4-point sparkle, concave sides
            let c = NSPoint(x: key.midX, y: key.midY), r: CGFloat = 5.6
            let star = NSBezierPath()
            let pts = (0..<4).map { i -> NSPoint in
                let a = CGFloat(i) * .pi / 2 + .pi / 2
                return NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            }
            star.move(to: pts[0])
            for i in 1...4 {
                // control point pulled out from the center gives the sparkle a fuller body
                let p0 = pts[i - 1], p1 = pts[i % 4]
                let m = NSPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                let cp = NSPoint(x: c.x + (m.x - c.x) * 0.28, y: c.y + (m.y - c.y) * 0.28)
                star.curve(to: p1, controlPoint1: cp, controlPoint2: cp)
            }
            star.close()
            (live ? NSColor.labelColor : NSColor.black).setFill(); star.fill()
            return true
        }
        img.isTemplate = !live
        return img
    }
}
