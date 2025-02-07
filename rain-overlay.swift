//
//  RainOverlay.swift
//  Example macOS SwiftUI app
//

import Cocoa
import Combine
import Metal
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import simd

// MARK: - RainSettings

struct RainSettings: Codable {
    var numberOfDrops: Int
    var speed: Float
    var angle: Float
    var color: NSColor
    var length: Float
    var smearFactor: Float
    var splashIntensity: Float
    var windEnabled: Bool
    var windIntensity: Float
    var mouseEnabled: Bool
    var mouseInfluenceIntensity: Float
    var maxFPS: Int

    enum CodingKeys: String, CodingKey {
        case numberOfDrops, speed, angle, color, length, smearFactor, splashIntensity, windEnabled,
            windIntensity, mouseEnabled, mouseInfluenceIntensity, maxFPS
    }

    struct ColorComponents: Codable {
        var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    }

    init(
        numberOfDrops: Int,
        speed: Float,
        angle: Float,
        color: NSColor,
        length: Float,
        smearFactor: Float,
        splashIntensity: Float,
        windEnabled: Bool,
        windIntensity: Float,
        mouseEnabled: Bool,
        mouseInfluenceIntensity: Float,
        maxFPS: Int = 30
    ) {
        self.numberOfDrops = numberOfDrops
        self.speed = speed
        self.angle = angle
        self.color = color
        self.length = length
        self.smearFactor = smearFactor
        self.splashIntensity = splashIntensity
        self.windEnabled = windEnabled
        self.windIntensity = windIntensity
        self.mouseEnabled = mouseEnabled
        self.mouseInfluenceIntensity = mouseInfluenceIntensity
        self.maxFPS = maxFPS
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        numberOfDrops = try container.decode(Int.self, forKey: .numberOfDrops)
        speed = try container.decode(Float.self, forKey: .speed)
        angle = try container.decode(Float.self, forKey: .angle)
        length = try container.decode(Float.self, forKey: .length)
        smearFactor = try container.decode(Float.self, forKey: .smearFactor)
        splashIntensity = try container.decode(Float.self, forKey: .splashIntensity)
        windEnabled = try container.decode(Bool.self, forKey: .windEnabled)
        windIntensity = try container.decode(Float.self, forKey: .windIntensity)
        mouseEnabled = try container.decode(Bool.self, forKey: .mouseEnabled)
        mouseInfluenceIntensity = try container.decode(Float.self, forKey: .mouseInfluenceIntensity)
        maxFPS = try container.decodeIfPresent(Int.self, forKey: .maxFPS) ?? 30

        let comps = try container.decode(ColorComponents.self, forKey: .color)
        color = NSColor(
            calibratedRed: comps.red,
            green: comps.green,
            blue: comps.blue,
            alpha: comps.alpha)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(numberOfDrops, forKey: .numberOfDrops)
        try container.encode(speed, forKey: .speed)
        try container.encode(angle, forKey: .angle)
        try container.encode(length, forKey: .length)
        try container.encode(smearFactor, forKey: .smearFactor)
        try container.encode(splashIntensity, forKey: .splashIntensity)
        try container.encode(windEnabled, forKey: .windEnabled)
        try container.encode(windIntensity, forKey: .windIntensity)
        try container.encode(mouseEnabled, forKey: .mouseEnabled)
        try container.encode(mouseInfluenceIntensity, forKey: .mouseInfluenceIntensity)
        try container.encode(maxFPS, forKey: .maxFPS)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if let rgb = color.usingColorSpace(.deviceRGB) {
            rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        let comps = ColorComponents(red: red, green: green, blue: blue, alpha: alpha)
        try container.encode(comps, forKey: .color)
    }
}

// MARK: - SettingsWindowController
class SettingsWindowController: NSWindowController {
    var rainView: RainView

    init(rainView: RainView) {
        self.rainView = rainView

        // Create our custom borderless window
        let window = SettingsWindow()
        super.init(window: window)

        // Access the SwiftUI hosting view inside the VFX -> HostingView chain
        if let settingsWindow = window.contentView?.subviews.first?.subviews.first
            as? NSHostingView<SettingsView>
        {
            // Pass the parentWindow reference to the SettingsView so it can close itself
            let settingsView = SettingsView(rainView: rainView, parentWindow: window)
            settingsWindow.rootView = settingsView
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - SettingsWindow
class SettingsWindow: NSWindow {
    init() {
        // Make window 800×600, borderless, and rounded corners
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isMovableByWindowBackground = true
        self.backgroundColor = NSColor.clear

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow

        // Rounded corners:
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 20
        visualEffect.layer?.masksToBounds = true

        let settingsView = SettingsView(rainView: nil, parentWindow: nil)
        let hostingView = NSHostingView(rootView: settingsView)

        visualEffect.frame = contentView?.bounds ?? .zero
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingView)

        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]

        self.contentView = visualEffect
    }
}

// MARK: - FluorescentNeonText
/// A random flicker neon glow effect
struct FluorescentNeonText: ViewModifier {
    @State private var flickerFactor: CGFloat = 1.0
    @State private var timer: Timer?

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    colors: [.pink, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            )
            .shadow(color: .pink.opacity(0.7 * flickerFactor), radius: 5, x: 0, y: 0)
            .shadow(color: .cyan.opacity(0.5 * flickerFactor), radius: 5, x: 0, y: 0)
            .onAppear { startFlicker() }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }

    private func startFlicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Double.random(in: 0.3...1.2),
            repeats: false
        ) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                flickerFactor = CGFloat.random(in: 0.6...1.0)
            }
            startFlicker()
        }
    }
}

extension View {
    func fluorescentNeon() -> some View {
        self.modifier(FluorescentNeonText())
    }
}

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var settingsStore: RainSettingsStore

    // A direct reference to the parent NSWindow so we can close it
    let parentWindow: NSWindow?

    init(rainView: RainView?, parentWindow: NSWindow?) {
        self.settingsStore = RainSettingsStore(rainView: rainView)
        self.parentWindow = parentWindow
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Rain Settings")
                .font(.system(size: 28, weight: .bold))
                .fluorescentNeon()

            // Two-column layout for numeric settings
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    NumericSettingRow(
                        title: "Number of Drops",
                        value: $settingsStore.numberOfDrops,
                        range: 0...1000,
                        step: 50
                    )
                    NumericSettingRow(
                        title: "Speed",
                        value: $settingsStore.speed,
                        range: 0.001...0.02,
                        step: 0.001
                    )
                    NumericSettingRow(
                        title: "Angle",
                        value: $settingsStore.angle,
                        range: -85...85,
                        step: 5
                    )
                }
                VStack(spacing: 20) {
                    NumericSettingRow(
                        title: "Length",
                        value: $settingsStore.length,
                        range: 0.005...0.2,
                        step: 0.005
                    )
                    NumericSettingRow(
                        title: "Wind Intensity",
                        value: $settingsStore.windIntensity,
                        range: 0.00001...0.001,
                        step: 0.0001
                    )
                    NumericSettingRow(
                        title: "Mouse Influence",
                        value: $settingsStore.mouseInfluenceIntensity,
                        range: 0...0.01,
                        step: 0.0005
                    )
                }
            }

            // One row for toggles
            HStack(spacing: 30) {
                ToggleSettingRow(
                    title: "Wind Enabled",
                    isOn: $settingsStore.windEnabled
                )
                ToggleSettingRow(
                    title: "Mouse Influence",
                    isOn: $settingsStore.mouseEnabled
                )
            }

            // Color picker
            ColorPicker("Rain Color", selection: $settingsStore.color)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.5), .purple.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
                .fluorescentNeon()

            // Load / Save Buttons
            HStack(spacing: 20) {
                Button("Load from JSON") { loadFromJSON() }
                    .fluorescentNeon()
                Button("Save to JSON") { saveToJSON() }
                    .fluorescentNeon()
            }
            .padding(.top, 10)

            Spacer()

            // "Close" at bottom
            HStack {
                Spacer()
                Button("Close") {
                    closeSettingsWindow()
                }
                .fluorescentNeon()
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                )
                .padding([.bottom, .trailing], 10)
            }
        }
        .padding(30)
        .frame(width: 800, height: 600)
    }

    // MARK: - JSON Load/Save

    private func loadFromJSON() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let newSettings = try JSONDecoder().decode(RainSettings.self, from: data)
                settingsStore.updateFrom(newSettings)
            } catch {
                print("Error loading settings from JSON: \(error)")
            }
        }
    }

    private func saveToJSON() {
        let panel = NSSavePanel()

        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }

        panel.nameFieldStringValue = "rain_settings.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try JSONEncoder().encode(settingsStore.currentSettings)
                try data.write(to: url)
            } catch {
                print("Error saving settings to JSON: \(error)")
            }
        }
    }

    // MARK: - Close the Settings Window
    /// Closes ONLY the settings window (not the entire app).
    private func closeSettingsWindow() {
        parentWindow?.close()
    }
}

// MARK: - NumericSettingRow
struct NumericSettingRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .fluorescentNeon()

            Slider(value: $value, in: range, step: step)

            Text(String(format: "%.4f", value))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - ToggleSettingRow
struct ToggleSettingRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .fluorescentNeon()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - RainSettingsStore
class RainSettingsStore: ObservableObject {
    private weak var rainView: RainView?

    @Published var numberOfDrops: Double {
        didSet { updateRainView { $0.numberOfDrops = Int(numberOfDrops) } }
    }
    @Published var speed: Double {
        didSet { updateRainView { $0.speed = Float(speed) } }
    }
    @Published var angle: Double {
        didSet { updateRainView { $0.angle = Float(angle) } }
    }
    @Published var length: Double {
        didSet { updateRainView { $0.length = Float(length) } }
    }

    @Published var color: Color {
        didSet {
            let nsColor = NSColor(color)
            updateRainView { $0.color = nsColor }
        }
    }

    @Published var windEnabled: Bool {
        didSet { updateRainView { $0.windEnabled = windEnabled } }
    }
    @Published var windIntensity: Double {
        didSet { updateRainView { $0.windIntensity = Float(windIntensity) } }
    }
    @Published var mouseEnabled: Bool {
        didSet { updateRainView { $0.mouseEnabled = mouseEnabled } }
    }
    @Published var mouseInfluenceIntensity: Double {
        didSet { updateRainView { $0.mouseInfluenceIntensity = Float(mouseInfluenceIntensity) } }
    }

    init(rainView: RainView?) {
        self.rainView = rainView

        let settings =
            rainView?.settings
            ?? RainSettings(
                numberOfDrops: 200,
                speed: 0.005,
                angle: 30.0,
                color: .white,
                length: 0.05,
                smearFactor: 4.0,
                splashIntensity: 0.3,
                windEnabled: true,
                windIntensity: 0.0001,
                mouseEnabled: false,
                mouseInfluenceIntensity: 0.001,
                maxFPS: 30
            )

        self.numberOfDrops = Double(settings.numberOfDrops)
        self.speed = Double(settings.speed)
        self.angle = Double(settings.angle)
        self.length = Double(settings.length)
        self.color = Color(settings.color)
        self.windEnabled = settings.windEnabled
        self.windIntensity = Double(settings.windIntensity)
        self.mouseEnabled = settings.mouseEnabled
        self.mouseInfluenceIntensity = Double(settings.mouseInfluenceIntensity)
    }

    var currentSettings: RainSettings {
        RainSettings(
            numberOfDrops: Int(numberOfDrops),
            speed: Float(speed),
            angle: Float(angle),
            color: NSColor(color),
            length: Float(length),
            smearFactor: rainView?.settings.smearFactor ?? 4.0,
            splashIntensity: rainView?.settings.splashIntensity ?? 0.3,
            windEnabled: windEnabled,
            windIntensity: Float(windIntensity),
            mouseEnabled: mouseEnabled,
            mouseInfluenceIntensity: Float(mouseInfluenceIntensity),
            maxFPS: rainView?.settings.maxFPS ?? 30
        )
    }

    func updateFrom(_ newSettings: RainSettings) {
        numberOfDrops = Double(newSettings.numberOfDrops)
        speed = Double(newSettings.speed)
        angle = Double(newSettings.angle)
        length = Double(newSettings.length)
        color = Color(newSettings.color)
        windEnabled = newSettings.windEnabled
        windIntensity = Double(newSettings.windIntensity)
        mouseEnabled = newSettings.mouseEnabled
        mouseInfluenceIntensity = Double(newSettings.mouseInfluenceIntensity)
    }

    private func updateRainView(_ update: (inout RainSettings) -> Void) {
        guard let rainView = rainView else { return }
        var settings = rainView.settings
        update(&settings)
        rainView.settings = settings
        rainView.createRaindrops()
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var rainView: RainView!
    var statusItem: NSStatusItem!
    var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBarItem()

        guard let screen = NSScreen.main else { return }
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.hasShadow = false
        window.alphaValue = 1.0

        if let device = MTLCreateSystemDefaultDevice() {
            let defaultSettings = RainSettings(
                numberOfDrops: 200,
                speed: 0.005,
                angle: 30.0,
                color: .white,
                length: 0.05,
                smearFactor: 4.0,
                splashIntensity: 0.3,
                windEnabled: true,
                windIntensity: 0.0001,
                mouseEnabled: false,
                mouseInfluenceIntensity: 0.001,
                maxFPS: 30
            )
            rainView = RainView(
                frame: window.contentView!.bounds,
                device: device,
                settings: defaultSettings
            )
            window.contentView = rainView
            rainView.layer?.isOpaque = false
            rainView.wantsLayer = true
            window.makeKeyAndOrderFront(nil)
        }
    }

    func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "🌧️"
            button.target = self
            button.action = #selector(toggleMenu(_:))
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Settings",
                action: #selector(showSettings),
                keyEquivalent: ","
            )
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleMenu(_ sender: Any?) {
        // Implement custom behavior if needed
    }

    @objc func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(rainView: rainView)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
}

// MARK: - RainView

class RainView: MTKView {
    var settings: RainSettings {
        didSet {
            self.preferredFramesPerSecond = settings.maxFPS
        }
    }

    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!

    private var raindrops: [Raindrop] = []
    private var splashes: [Splash] = []

    // Wind and ambient environment
    private var wind: Float = 0.0
    private var ambientColor: SIMD4<Float> = SIMD4<Float>(0.05, 0.05, 0.1, 1.0)
    private var time: Float = 0.0

    private var currentAngle: Float {
        return settings.angle * .pi / 180.0
    }

    struct Raindrop {
        var position: SIMD2<Float>
        var speed: Float
        var length: Float
        var isSpecial: Bool
        var colorIntensity: Float
    }

    struct Splash {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var life: Float
        var startLife: Float
        var intensity: Float

        mutating func update() {
            life -= 0.016
            velocity *= 0.99
            velocity.y -= 0.003
            position += velocity
        }

        var alpha: Float {
            let norm = max(life / startLife, 0)
            return norm * norm * intensity
        }
    }

    struct RainUniforms {
        var rainColor: SIMD4<Float>
        var ambientColor: SIMD4<Float>
    }

    private func simd4(from color: NSColor) -> SIMD4<Float> {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return SIMD4<Float>(1, 1, 1, 1) }
        return SIMD4<Float>(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent),
            Float(rgb.alphaComponent)
        )
    }

    private func newDropPosition() -> SIMD2<Float> {
        let useAngleBias = abs(settings.angle) > 15
        let spawnFromSide =
            useAngleBias
            ? Float.random(in: 0...1) > 0.3
            : Float.random(in: 0...1) > (1 / (1 + Float(bounds.width / bounds.height)))

        if !spawnFromSide {
            let x = Float.random(in: -1...1)
            return SIMD2<Float>(x, 1)
        } else {
            let x: Float
            if settings.angle > 0 {
                x = Float.random(in: -1 ... -0.8)
            } else if settings.angle < 0 {
                x = Float.random(in: 0.8...1)
            } else {
                x = Float.random(in: -1...1)
            }
            let y = Float.random(in: -1...1)
            return SIMD2<Float>(x, y)
        }
    }

    init(frame frameRect: CGRect, device: MTLDevice, settings: RainSettings) {
        self.settings = settings
        super.init(frame: frameRect, device: device)

        self.preferredFramesPerSecond = settings.maxFPS
        self.commandQueue = device.makeCommandQueue()
        self.clearColor = MTLClearColorMake(0, 0, 0, 0)
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = false

        setupPipeline()
        createRaindrops()

        self.enableSetNeedsDisplay = true
        self.isPaused = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPipeline() {
        guard let device = self.device else { return }

        let shaderSource = """
            #include <metal_stdlib>
            using namespace metal;

            struct Vertex {
                float2 position;
                float alpha;
            };

            struct VertexOut {
                float4 position [[position]];
                float alpha;
            };

            struct RainUniforms {
                float4 rainColor;
                float4 ambientColor;
            };

            vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                                          const device Vertex *vertices [[buffer(0)]]) {
                VertexOut out;
                out.position = float4(vertices[vertexID].position, 0.0, 1.0);
                out.alpha = vertices[vertexID].alpha;
                return out;
            }

            fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                           constant RainUniforms &uniforms [[buffer(1)]]) {
                return (uniforms.rainColor * in.alpha + uniforms.ambientColor);
            }
            """.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor =
                .oneMinusSourceAlpha

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    private func updateEnvironment() {
        if settings.windEnabled {
            wind += Float.random(in: -settings.windIntensity...settings.windIntensity)
            wind = min(max(wind, -0.003), 0.003)
            if Float.random(in: 0...1) < 0.1 {
                settings.angle += wind * 30
                settings.angle = min(max(settings.angle, -85), 85)
            }
        } else {
            wind = 0
        }

        time += 0.016
        ambientColor = SIMD4<Float>(
            0.05 + 0.01 * sin(time * 0.05),
            0.05 + 0.01 * sin(time * 0.05 + 2.0),
            0.1 + 0.01 * sin(time * 0.05 + 4.0),
            1.0
        )
    }

    func createRaindrops() {
        raindrops.removeAll()
        for _ in 0..<settings.numberOfDrops {
            let pos = newDropPosition()
            let special = Float.random(in: 0...1) < 0.01

            let lengthRange = settings.length * 0.5...settings.length * 2.0
            let randomLength = Float.random(in: lengthRange)
            let normalizedLength =
                (randomLength - lengthRange.lowerBound)
                / (lengthRange.upperBound - lengthRange.lowerBound)
            let colorIntensity = 0.4 + (normalizedLength * 0.6)

            let drop = Raindrop(
                position: pos,
                speed: Float.random(in: settings.speed...(settings.speed * 2)),
                length: randomLength,
                isSpecial: special,
                colorIntensity: colorIntensity
            )
            raindrops.append(drop)
        }
    }

    private func createSplash(at position: SIMD2<Float>, intensity: Float) {
        let count = Int.random(in: 3...5)
        for _ in 0..<count {
            let randomAngle = Float.random(in: (Float.pi / 6)...(5 * Float.pi / 6))
            let speed = Float.random(in: 0.012...0.024)
            let vel = SIMD2<Float>(cos(randomAngle) * speed, sin(randomAngle) * speed * 3.0)
            let life = Float.random(in: 0.4...0.8)
            let splash = Splash(
                position: position,
                velocity: vel,
                life: life,
                startLife: life,
                intensity: intensity
            )
            splashes.append(splash)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        updateEnvironment()

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = currentRenderPassDescriptor,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
            )
        else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)

        var uniforms = RainUniforms(
            rainColor: simd4(from: settings.color),
            ambientColor: ambientColor
        )
        renderEncoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<RainUniforms>.stride,
            index: 1
        )

        var raindropVertices: [Vertex] = []
        var splashVertices: [Vertex] = []

        // --- Update and Render Raindrops ---
        for i in 0..<raindrops.count {
            let effectiveSpeed =
                raindrops[i].isSpecial
                ? raindrops[i].speed * 0.5
                : raindrops[i].speed

            var dx = sin(currentAngle) * effectiveSpeed + wind
            let dy = -cos(currentAngle) * effectiveSpeed

            if settings.mouseEnabled {
                let globalMouse = NSEvent.mouseLocation
                if let screen = NSScreen.main {
                    let frame = screen.frame
                    let normX = ((globalMouse.x - frame.origin.x) / frame.width) * 2 - 1
                    let normY = ((globalMouse.y - frame.origin.y) / frame.height) * 2 - 1
                    let mousePos = SIMD2<Float>(Float(normX), Float(normY))
                    let diff = mousePos - raindrops[i].position
                    let influence = diff * settings.mouseInfluenceIntensity
                    dx += influence.x
                }
            }

            raindrops[i].position.x += dx
            raindrops[i].position.y += dy

            if raindrops[i].position.y < -1 {
                if raindrops[i].colorIntensity > 0.85 {
                    createSplash(
                        at: raindrops[i].position,
                        intensity: raindrops[i].colorIntensity
                    )
                }

                let pos = newDropPosition()
                let special = Float.random(in: 0...1) < 0.01
                let lengthRange = settings.length * 0.5...settings.length * 2.0
                let randomLength = Float.random(in: lengthRange)
                let normalizedLength =
                    (randomLength - lengthRange.lowerBound)
                    / (lengthRange.upperBound - lengthRange.lowerBound)
                let colorIntensity = 0.4 + (normalizedLength * 0.6)

                raindrops[i].position = pos
                raindrops[i].isSpecial = special
                raindrops[i].length = randomLength
                raindrops[i].colorIntensity = colorIntensity
            }

            let dropDir = SIMD2<Float>(sin(currentAngle), -cos(currentAngle))
            let dropLength = raindrops[i].length * 0.5
            let dropEnd = raindrops[i].position + dropDir * dropLength

            let dropAlpha = raindrops[i].colorIntensity
            raindropVertices.append(Vertex(position: raindrops[i].position, alpha: dropAlpha))
            raindropVertices.append(Vertex(position: dropEnd, alpha: dropAlpha))

            if raindrops[i].isSpecial && raindrops[i].colorIntensity > 0.85 {
                let smearLength = raindrops[i].length * settings.smearFactor
                let smearEnd = raindrops[i].position + dropDir * smearLength
                let smearAlpha = raindrops[i].colorIntensity * 0.3
                raindropVertices.append(Vertex(position: raindrops[i].position, alpha: smearAlpha))
                raindropVertices.append(Vertex(position: smearEnd, alpha: smearAlpha))
            }
        }

        // Update & Render Splashes
        for i in 0..<splashes.count {
            splashes[i].update()
        }
        splashes = splashes.filter { $0.life > 0 }

        for splash in splashes {
            let v = splash.velocity
            let mag = simd_length(v)
            let offset: SIMD2<Float>
            if mag > 0.0001 {
                offset = (v / mag) * (0.1 * settings.splashIntensity)
            } else {
                offset = SIMD2<Float>(
                    0.1 * settings.splashIntensity, 0.1 * settings.splashIntensity)
            }
            let start = splash.position
            let end = splash.position + offset
            let a = splash.alpha * settings.splashIntensity

            splashVertices.append(Vertex(position: start, alpha: a))
            splashVertices.append(Vertex(position: end, alpha: a))
        }

        // --- Encode Raindrops ---
        raindropVertices.withUnsafeBytes { bufferPointer in
            renderEncoder.setVertexBytes(
                bufferPointer.baseAddress!,
                length: raindropVertices.count * MemoryLayout<Vertex>.stride,
                index: 0
            )
        }
        renderEncoder.drawPrimitives(
            type: .line,
            vertexStart: 0,
            vertexCount: raindropVertices.count
        )

        // --- Encode Splashes ---
        splashVertices.withUnsafeBytes { bufferPointer in
            renderEncoder.setVertexBytes(
                bufferPointer.baseAddress!,
                length: splashVertices.count * MemoryLayout<Vertex>.stride,
                index: 0
            )
        }
        renderEncoder.drawPrimitives(
            type: .line,
            vertexStart: 0,
            vertexCount: splashVertices.count
        )

        renderEncoder.endEncoding()

        if let drawable = currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}

// MARK: - Vertex

struct Vertex {
    var position: SIMD2<Float>
    var alpha: Float
}
