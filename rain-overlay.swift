//
//  RainOverlay.swift
//  Example macOS SwiftUI app
//
//  This file implements a rain and snow overlay using Metal and SwiftUI.
//  It includes a settings UI, a custom Metal view (RainView) that simulates rain
//  and snow (with accumulation), and uses a fixed‑size heap‑allocated pool for
//  snowflake state. The settings panel now includes a GitHub link on the left and a
//  Close button on the right. When snow is enabled, the panel height is increased.
//

import Cocoa
import Combine
import CoreGraphics
import Metal
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import simd

// MARK: - RainSettings

/// Represents the settings for the rain and snow simulation.
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
    var rainEnabled: Bool
    var snowEnabled: Bool
    /// The base snow accumulation threshold (normalized –1 = bottom, 1 = top).
    /// Set to –1.0 so falling snow remains visible.
    var snowAccumulationThreshold: Float

    enum CodingKeys: String, CodingKey {
        case numberOfDrops, speed, angle, color, length, smearFactor, splashIntensity, windEnabled,
            windIntensity, mouseEnabled, mouseInfluenceIntensity, maxFPS, rainEnabled, snowEnabled,
            snowAccumulationThreshold
    }

    /// Helper structure to encode/decode NSColor.
    struct ColorComponents: Codable {
        var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    }

    // MARK: Initializers

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
        maxFPS: Int = 30,
        rainEnabled: Bool = true,
        snowEnabled: Bool = false,
        snowAccumulationThreshold: Float = -1.0
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
        self.rainEnabled = rainEnabled
        self.snowEnabled = snowEnabled
        self.snowAccumulationThreshold = snowAccumulationThreshold
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
        rainEnabled = try container.decodeIfPresent(Bool.self, forKey: .rainEnabled) ?? true
        snowEnabled = try container.decodeIfPresent(Bool.self, forKey: .snowEnabled) ?? false
        snowAccumulationThreshold =
            try container.decodeIfPresent(Float.self, forKey: .snowAccumulationThreshold) ?? -1.0

        let comps = try container.decode(ColorComponents.self, forKey: .color)
        color = NSColor(
            calibratedRed: comps.red, green: comps.green, blue: comps.blue, alpha: comps.alpha)
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
        try container.encode(rainEnabled, forKey: .rainEnabled)
        try container.encode(snowEnabled, forKey: .snowEnabled)
        try container.encode(snowAccumulationThreshold, forKey: .snowAccumulationThreshold)

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

// MARK: - Settings Window & Controller

/// A custom NSWindowController hosting the settings view.
class SettingsWindowController: NSWindowController {
    var rainView: RainView
    init(rainView: RainView) {
        self.rainView = rainView
        let window = SettingsWindow(rainView: rainView)
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A custom NSWindow that displays the settings using a visual effect.
class SettingsWindow: NSWindow {
    init(rainView: RainView) {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 650)  // Base height; controlled by the SwiftUI view.
        super.init(
            contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear

        let visualEffect = NSVisualEffectView(frame: contentRect)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 20
        visualEffect.layer?.masksToBounds = true

        let settingsView = SettingsView(rainView: rainView, parentWindow: self)
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingView)
        self.contentView = visualEffect
    }
}

// MARK: - Neon Text Modifier

/// Applies a neon flickering effect to text.
struct FluorescentNeonText: ViewModifier {
    @State private var flickerFactor: CGFloat = 1.0
    @State private var timer: Timer?

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    colors: [.pink, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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
        timer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 0.3...1.2), repeats: false)
        { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                flickerFactor = CGFloat.random(in: 0.6...1.0)
            }
            startFlicker()
        }
    }
}

extension View {
    func fluorescentNeon() -> some View { self.modifier(FluorescentNeonText()) }
}

// MARK: - Settings View

/// The SwiftUI view for adjusting simulation settings.
/// When snow is enabled, the panel height is increased to 900.
struct SettingsView: View {
    @ObservedObject var settingsStore: RainSettingsStore
    let parentWindow: NSWindow?

    init(rainView: RainView?, parentWindow: NSWindow?) {
        self.settingsStore = RainSettingsStore(rainView: rainView)
        self.parentWindow = parentWindow
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Rain & Snow Settings")
                .font(.system(size: 28, weight: .bold))
                .fluorescentNeon()

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    NumericSettingRow(
                        title: "Number of Drops", value: $settingsStore.numberOfDrops,
                        range: 0...1000, step: 50)
                    NumericSettingRow(
                        title: "Speed", value: $settingsStore.speed, range: 0.001...0.02,
                        step: 0.001)
                    NumericSettingRow(
                        title: "Angle", value: $settingsStore.angle, range: -85...85, step: 5)
                }
                VStack(spacing: 20) {
                    NumericSettingRow(
                        title: "Length", value: $settingsStore.length, range: 0.005...0.2,
                        step: 0.005)
                    NumericSettingRow(
                        title: "Wind Intensity", value: $settingsStore.windIntensity,
                        range: 0.00001...0.001, step: 0.0001)
                    NumericSettingRow(
                        title: "Mouse Influence", value: $settingsStore.mouseInfluenceIntensity,
                        range: 0...0.01, step: 0.0005)
                }
            }

            HStack(spacing: 30) {
                ToggleSettingRow(title: "Rain Enabled", isOn: $settingsStore.rainEnabled)
                ToggleSettingRow(title: "Wind Enabled", isOn: $settingsStore.windEnabled)
                ToggleSettingRow(title: "Mouse Influence", isOn: $settingsStore.mouseEnabled)
                ToggleSettingRow(title: "Snow Enabled", isOn: $settingsStore.snowEnabled)
            }
            if settingsStore.snowEnabled {
                NumericSettingRow(
                    title: "Base Snow Accumulation",
                    value: $settingsStore.snowAccumulationThreshold, range: -1.0...0.0, step: 0.01)
            }

            ColorPicker("Rain Color", selection: $settingsStore.color)
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.5), .purple.opacity(0.5)],
                                startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                )
                .fluorescentNeon()

            HStack(spacing: 20) {
                Button("Load from JSON") { loadFromJSON() }
                    .fluorescentNeon()
                Button("Save to JSON") { saveToJSON() }
                    .fluorescentNeon()
            }
            .padding(.top, 10)

            Spacer()

            // Lower controls: GitHub link on the left and Close button on the right.
            HStack {
                Link("GitHub", destination: URL(string: "https://github.com/ztomer/rain-overlay")!)
                    .fluorescentNeon()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                    )
                Spacer()
                Button("Close") { closeSettingsWindow() }
                    .fluorescentNeon()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                    )
                    .padding(.trailing, 10)
            }
        }
        .padding(30)
        .frame(width: 800, height: settingsStore.snowEnabled ? 900 : 650)
    }

    // MARK: JSON Helpers

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

    private func closeSettingsWindow() { parentWindow?.close() }
}

// MARK: - Numeric & Toggle Setting Rows

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
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5)))
    }
}

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
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5)))
    }
}

// MARK: - RainSettingsStore

/// An observable object that holds the simulation settings and updates the RainView.
class RainSettingsStore: ObservableObject {
    private weak var rainView: RainView?

    @Published var numberOfDrops: Double {
        didSet { updateRainView { $0.numberOfDrops = Int(numberOfDrops) } }
    }
    @Published var speed: Double { didSet { updateRainView { $0.speed = Float(speed) } } }
    @Published var angle: Double { didSet { updateRainView { $0.angle = Float(angle) } } }
    @Published var length: Double { didSet { updateRainView { $0.length = Float(length) } } }
    @Published var color: Color { didSet { updateRainView { $0.color = NSColor(color) } } }
    @Published var windEnabled: Bool { didSet { updateRainView { $0.windEnabled = windEnabled } } }
    @Published var windIntensity: Double {
        didSet { updateRainView { $0.windIntensity = Float(windIntensity) } }
    }
    @Published var mouseEnabled: Bool {
        didSet { updateRainView { $0.mouseEnabled = mouseEnabled } }
    }
    @Published var mouseInfluenceIntensity: Double {
        didSet { updateRainView { $0.mouseInfluenceIntensity = Float(mouseInfluenceIntensity) } }
    }
    @Published var rainEnabled: Bool { didSet { updateRainView { $0.rainEnabled = rainEnabled } } }
    @Published var snowEnabled: Bool {
        didSet {
            updateRainView { $0.snowEnabled = snowEnabled }
            if !snowEnabled { rainView?.destroySnowflakePool() }
        }
    }
    @Published var snowAccumulationThreshold: Double {
        didSet {
            updateRainView { $0.snowAccumulationThreshold = Float(snowAccumulationThreshold) }
        }
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
                maxFPS: 30,
                rainEnabled: true,
                snowEnabled: false,
                snowAccumulationThreshold: -1.0
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
        self.rainEnabled = settings.rainEnabled
        self.snowEnabled = settings.snowEnabled
        self.snowAccumulationThreshold = Double(settings.snowAccumulationThreshold)
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
            maxFPS: rainView?.settings.maxFPS ?? 30,
            rainEnabled: rainEnabled,
            snowEnabled: snowEnabled,
            snowAccumulationThreshold: Float(snowAccumulationThreshold)
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
        rainEnabled = newSettings.rainEnabled
        snowEnabled = newSettings.snowEnabled
        snowAccumulationThreshold = Double(newSettings.snowAccumulationThreshold)
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

/// The application delegate sets up the main window, status bar, and simulation view.
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
            // For testing, enable snow.
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
                maxFPS: 30,
                rainEnabled: true,
                snowEnabled: true,
                snowAccumulationThreshold: -1.0
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
            NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleMenu(_ sender: Any?) {}
    @objc func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(rainView: rainView)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quitApp() { NSApplication.shared.terminate(self) }
}

// MARK: - Vertex

/// A vertex used for rendering, with a 2D position and alpha value.
struct Vertex {
    var position: SIMD2<Float>
    var alpha: Float
}

// MARK: - Snowflake Structures

/// Basic data for a snowflake.
struct Snowflake {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var size: Float
    var wobblePhase: Float  // For side-to-side motion.
    var wobbleAmplitude: Float  // Magnitude of wobble.
}

/// State for a snowflake including rendering parameters.
struct SnowflakeState {
    var flake: Snowflake
    var opacity: Float  // Fade-in/out value.
    var rotation: Float  // Rotation angle.
    var isActive: Bool  // Whether this snowflake is currently active.
}

// MARK: - RainView

/// A custom MTKView that renders rain and snow (with accumulation) using Metal.
class RainView: MTKView {
    // Simulation settings.
    var settings: RainSettings {
        didSet { self.preferredFramesPerSecond = settings.maxFPS }
    }

    // Metal objects.
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!

    // Rain simulation.
    private var raindrops: [Raindrop] = []
    private var splashes: [Splash] = []

    // Snow accumulation.
    /// An array representing the current accumulated snow height for each horizontal segment.
    private var snowPiles: [Float] = []
    /// The number of horizontal segments used for accumulation.
    private let snowPileResolution: Int = 100
    /// The maximum accumulation level – snow will accumulate up to this value.
    private let maxAccumulation: Float = -0.8

    // Ambient environment.
    private var wind: Float = 0.0
    private var ambientColor: SIMD4<Float> = SIMD4<Float>(0.05, 0.05, 0.1, 1.0)
    private var time: Float = 0.0
    private var currentAngle: Float { settings.angle * .pi / 180.0 }

    // MARK: Fixed-Size Snowflake Pool

    /// Number of slots in the snowflake pool.
    private var _poolSize: Int = 200
    /// The heap-allocated fixed-size pool for snowflake states.
    private var _snowflakePool: UnsafeMutableBufferPointer<SnowflakeState>?

    // MARK: Rain Structures

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

    /// Uniforms for the Metal shader.
    struct RainUniforms {
        var rainColor: SIMD4<Float>
        var ambientColor: SIMD4<Float>
    }

    // MARK: Initialization

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

        // Initialize snow accumulation to ground level (-1.0 everywhere).
        if settings.snowEnabled {
            snowPiles = [Float](repeating: -1.0, count: snowPileResolution)
        }

        self.enableSetNeedsDisplay = true
        self.isPaused = false

        // Allocate the fixed-size pool for snowflakes.
        initializeSnowflakePool(with: _poolSize)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { destroySnowflakePool() }

    // MARK: Metal Pipeline Setup

    /// Sets up the Metal render pipeline.
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

    // MARK: Environment & Rain Updates

    /// Updates wind and ambient color.
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

    /// Creates the raindrop array based on the settings.
    func createRaindrops() {
        raindrops.removeAll()
        if settings.rainEnabled {
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
    }

    /// Computes a new random spawn position for a raindrop.
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
            let x: Float =
                (settings.angle > 0)
                ? Float.random(in: -1 ... -0.8)
                : (settings.angle < 0 ? Float.random(in: 0.8...1) : Float.random(in: -1...1))
            let y = Float.random(in: -1...1)
            return SIMD2<Float>(x, y)
        }
    }

    // MARK: Fixed-Size Snowflake Pool Management

    /// Allocates and initializes the snowflake pool.
    func initializeSnowflakePool(with size: Int) {
        if let pool = _snowflakePool {
            pool.baseAddress?.deinitialize(count: pool.count)
            pool.baseAddress?.deallocate()
        }
        _poolSize = size
        let pointer = UnsafeMutablePointer<SnowflakeState>.allocate(capacity: size)
        for i in 0..<size {
            pointer.advanced(by: i).initialize(
                to:
                    SnowflakeState(
                        flake: createSnowflake(),
                        opacity: 0.0,
                        rotation: Float.random(in: 0..<(2 * .pi)),
                        isActive: false
                    )
            )
        }
        _snowflakePool = UnsafeMutableBufferPointer(start: pointer, count: size)
    }

    /// Reinitializes the pool with a new size.
    func reinitializeSnowflakePool(newSize: Int) { initializeSnowflakePool(with: newSize) }

    /// Returns the index of a free (inactive) slot.
    func findFreeSlotInPool() -> Int? {
        guard let pool = _snowflakePool else { return nil }
        for i in 0..<pool.count {
            if !pool[i].isActive { return i }
        }
        return nil
    }

    /// Destroys the snowflake pool.
    func destroySnowflakePool() {
        if let pool = _snowflakePool {
            pool.baseAddress?.deinitialize(count: pool.count)
            pool.baseAddress?.deallocate()
            _snowflakePool = nil
        }
    }

    // MARK: Snowflake Creation & Clearing

    /// Creates a new snowflake positioned above the top.
    func createSnowflake() -> Snowflake {
        let x = Float.random(in: -1...1)
        let y = 1 + Float.random(in: 0.05...0.15)
        let size = Float.random(in: 0.01...0.02)
        let vy = -Float.random(in: 0.001...0.003)
        let vx = Float.random(in: -0.0005...0.0005)
        let wobblePhase = Float.random(in: 0...2 * .pi)
        let wobbleAmplitude = Float.random(in: 0.0001...0.0003)
        return Snowflake(
            position: SIMD2<Float>(x, y),
            velocity: SIMD2<Float>(vx, vy),
            size: size,
            wobblePhase: wobblePhase,
            wobbleAmplitude: wobbleAmplitude
        )
    }

    /// Deactivates all snowflakes and resets snow accumulation.
    func clearSnow() {
        if let pool = _snowflakePool {
            for i in 0..<pool.count { pool[i].isActive = false }
        }
        snowPiles = [Float](repeating: -1.0, count: snowPileResolution)
    }

    // MARK: Window Accumulation Levels

    /// Computes the target accumulation levels for each horizontal segment based on other windows.
    func computeWindowAccumulationLevels() -> [Float] {
        var levels = [Float](repeating: -1.0, count: snowPileResolution)
        if let windowListInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        {
            let myWindowNumber = self.window?.windowNumber
            let screenHeight = NSScreen.main?.frame.height ?? 1.0
            let screenWidth = NSScreen.main?.frame.width ?? 1.0
            let offset = Float((30.0 / screenHeight) * 2)
            for info in windowListInfo {
                if let ownerName = info[kCGWindowOwnerName as String] as? String,
                    ownerName == "Dock" || ownerName == "Window Server"
                {
                    continue
                }
                if let windowNumber = info[kCGWindowNumber as String] as? Int,
                    windowNumber == myWindowNumber
                {
                    continue
                }
                if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                    let x = boundsDict["X"] as? CGFloat,
                    let y = boundsDict["Y"] as? CGFloat,
                    let width = boundsDict["Width"] as? CGFloat,
                    let height = boundsDict["Height"] as? CGFloat
                {
                    let topEdge = y + height
                    let normalizedTop = Float((topEdge / screenHeight) * 2 - 1)
                    let adjustedTop = normalizedTop - offset
                    let normLeft = Float((x / screenWidth) * 2 - 1)
                    let normRight = Float(((x + width) / screenWidth) * 2 - 1)
                    for i in 0..<levels.count {
                        let segX = Float(i) / Float(levels.count - 1) * 2 - 1
                        if segX >= normLeft && segX <= normRight {
                            // Only accumulate on windows that are low (their top is below 0).
                            if adjustedTop < 0 {
                                levels[i] = max(levels[i], adjustedTop)
                            }
                        }
                    }
                }
            }
        }
        return levels
    }

    // MARK: Draw Loop

    /// The main drawing routine.
    override func draw(_ dirtyRect: NSRect) {
        updateEnvironment()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = currentRenderPassDescriptor,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        var uniforms = RainUniforms(
            rainColor: simd4(from: settings.color),
            ambientColor: ambientColor
        )
        renderEncoder.setFragmentBytes(
            &uniforms, length: MemoryLayout<RainUniforms>.stride, index: 1)

        // --- Rain & Splash Rendering ---
        var raindropVertices: [Vertex] = []
        var splashVertices: [Vertex] = []

        if settings.rainEnabled {
            for i in 0..<raindrops.count {
                let effectiveSpeed =
                    raindrops[i].isSpecial ? raindrops[i].speed * 0.5 : raindrops[i].speed
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
                            at: raindrops[i].position, intensity: raindrops[i].colorIntensity)
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
                    raindropVertices.append(
                        Vertex(position: raindrops[i].position, alpha: smearAlpha))
                    raindropVertices.append(Vertex(position: smearEnd, alpha: smearAlpha))
                }
            }
        } else {
            raindrops.removeAll()
            splashes.removeAll()
        }

        for i in 0..<splashes.count { splashes[i].update() }
        splashes = splashes.filter { $0.life > 0 }
        for splash in splashes {
            let v = splash.velocity
            let mag = simd_length(v)
            let offset: SIMD2<Float> =
                (mag > 0.0001)
                ? (v / mag) * (0.1 * settings.splashIntensity)
                : SIMD2<Float>(0.1 * settings.splashIntensity, 0.1 * settings.splashIntensity)
            let start = splash.position
            let end = splash.position + offset
            let a = splash.alpha * settings.splashIntensity
            splashVertices.append(Vertex(position: start, alpha: a))
            splashVertices.append(Vertex(position: end, alpha: a))
        }

        raindropVertices.withUnsafeBytes { bufferPointer in
            renderEncoder.setVertexBytes(
                bufferPointer.baseAddress!,
                length: raindropVertices.count * MemoryLayout<Vertex>.stride,
                index: 0)
        }
        renderEncoder.drawPrimitives(
            type: .line, vertexStart: 0, vertexCount: raindropVertices.count)
        splashVertices.withUnsafeBytes { bufferPointer in
            renderEncoder.setVertexBytes(
                bufferPointer.baseAddress!,
                length: splashVertices.count * MemoryLayout<Vertex>.stride,
                index: 0)
        }
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: splashVertices.count)

        // --- Snow Simulation & Accumulation ---
        if settings.snowEnabled {
            let currentTime = CACurrentMediaTime()
            let deltaTime = Float(currentTime - lastUpdateTime)
            lastUpdateTime = currentTime
            simulateAndRenderSnow(deltaTime: deltaTime, renderEncoder: renderEncoder)
        }

        renderEncoder.endEncoding()
        if let drawable = currentDrawable { commandBuffer.present(drawable) }
        commandBuffer.commit()
    }

    private var lastUpdateTime: CFTimeInterval = CACurrentMediaTime()

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
}

// MARK: - Snow Simulation Extension

extension RainView {
    /// Converts an NSColor to a SIMD4<Float> (assuming deviceRGB).
    private func simd4(from color: NSColor) -> SIMD4<Float> {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return SIMD4<Float>(1, 1, 1, 1) }
        return SIMD4<Float>(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent),
            Float(rgb.alphaComponent))
    }

    /// Simulates snowflake physics, checks for accumulation collisions, renders active snowflakes,
    /// and draws a filled accumulation layer.
    ///
    /// The algorithm:
    /// 1. Initialize snowPiles to –1.0 (ground) for each segment.
    /// 2. Compute windowLevels from non‑system windows.
    /// 3. For each active snowflake, determine its horizontal segment.
    /// 4. Compute effectiveThreshold as follows:
    ///    - If a window is present (windowLevels[segIndex] < 0), use max(snowPiles[segIndex], windowLevels[segIndex]).
    ///    - Otherwise, use snowPiles[segIndex].
    /// 5. If the snowflake’s y‑position is below (effectiveThreshold + its size), then increase
    ///    snowPiles (using a higher rate if on the ground, a lower rate if on a window) but cap it at maxAccumulation,
    ///    and deactivate the snowflake.
    /// 6. Spawn new snowflakes if active count is below target.
    /// 7. Draw active snowflakes, then draw a triangle strip from snowPiles (accumulated snow) to –1 (ground).
    ///
    /// - Parameters:
    ///   - deltaTime: The time elapsed since the last frame.
    ///   - renderEncoder: The Metal render command encoder.
    func simulateAndRenderSnow(deltaTime: Float, renderEncoder: MTLRenderCommandEncoder) {
        guard let pool = _snowflakePool else { return }

        let windowLevels = computeWindowAccumulationLevels()

        var activeCount = 0
        for i in 0..<pool.count {
            var state = pool[i]
            if !state.isActive { continue }
            activeCount += 1

            state.opacity = min(state.opacity + deltaTime * 2.0, 1.0)
            state.rotation += deltaTime * Float.random(in: 0.5...1.5)
            state.flake.wobblePhase += deltaTime * 2.0
            let wobbleOffset = sin(state.flake.wobblePhase) * state.flake.wobbleAmplitude
            state.flake.position.x += state.flake.velocity.x + wobbleOffset
            state.flake.position.y += state.flake.velocity.y

            let normalizedX = (state.flake.position.x + 1) / 2
            let seg = Int(normalizedX * Float(snowPileResolution - 1))
            let segIndex = max(0, min(snowPileResolution - 1, seg))
            let windowThreshold = windowLevels[segIndex]
            // If a low window is present (windowThreshold < 0), use its top; otherwise, use the current accumulation.
            let effectiveThreshold: Float =
                (windowThreshold < 0)
                ? max(snowPiles[segIndex], windowThreshold) : snowPiles[segIndex]

            if state.flake.position.y <= effectiveThreshold + state.flake.size {
                // Use a higher accumulation rate for ground and a lower rate for windows.
                let rate: Float =
                    (windowThreshold < 0)
                    ? Float.random(in: 0.05...0.1) : Float.random(in: 0.2...0.3)
                let deltaAccum = state.flake.size * rate
                snowPiles[segIndex] = min(snowPiles[segIndex] + deltaAccum, maxAccumulation)
                if segIndex > 0 {
                    snowPiles[segIndex - 1] = min(
                        snowPiles[segIndex - 1] + deltaAccum * 0.5, maxAccumulation)
                }
                if segIndex < snowPileResolution - 1 {
                    snowPiles[segIndex + 1] = min(
                        snowPiles[segIndex + 1] + deltaAccum * 0.5, maxAccumulation)
                }
                state.isActive = false
            } else if state.flake.position.y < -1 {
                state.isActive = false
            }
            pool[i] = state
        }

        // Spawn new snowflakes if necessary.
        let targetActiveSnowflakes = 50
        if activeCount < targetActiveSnowflakes {
            for i in 0..<pool.count {
                if activeCount >= targetActiveSnowflakes { break }
                if !pool[i].isActive {
                    let newState = SnowflakeState(
                        flake: createSnowflake(),
                        opacity: 0.0,
                        rotation: Float.random(in: 0..<(2 * .pi)),
                        isActive: true
                    )
                    pool[i] = newState
                    activeCount += 1
                }
            }
        }

        // Build vertex list for active snowflakes.
        var snowflakeVertices: [Vertex] = []
        for i in 0..<pool.count {
            let state = pool[i]
            if !state.isActive { continue }
            let s = state.flake.size
            let x = state.flake.position.x
            let y = state.flake.position.y
            let rotation = state.rotation
            let opacity = state.opacity
            for j in 0..<6 {
                let angle = rotation + Float(j) * (.pi / 3)
                let startX = x + cos(angle) * (s * 0.5)
                let startY = y + sin(angle) * (s * 0.5)
                let endX = x - cos(angle) * (s * 0.5)
                let endY = y - sin(angle) * (s * 0.5)
                snowflakeVertices.append(
                    Vertex(position: SIMD2<Float>(startX, startY), alpha: opacity))
                snowflakeVertices.append(Vertex(position: SIMD2<Float>(endX, endY), alpha: opacity))
            }
        }

        if !snowflakeVertices.isEmpty {
            snowflakeVertices.withUnsafeBytes { bufferPointer in
                renderEncoder.setVertexBytes(
                    bufferPointer.baseAddress!,
                    length: snowflakeVertices.count * MemoryLayout<Vertex>.stride,
                    index: 0)
            }
            renderEncoder.drawPrimitives(
                type: .line, vertexStart: 0, vertexCount: snowflakeVertices.count)
        }

        // --- Draw Snow Accumulation Layer ---
        var accumulationVertices: [Vertex] = []
        for i in 0..<snowPileResolution {
            let x = Float(i) / Float(snowPileResolution - 1) * 2 - 1
            let y = snowPiles[i]
            accumulationVertices.append(Vertex(position: SIMD2<Float>(x, y), alpha: 1.0))
            accumulationVertices.append(Vertex(position: SIMD2<Float>(x, -1), alpha: 1.0))
        }
        var accumulationUniforms = RainUniforms(
            rainColor: SIMD4<Float>(1, 1, 1, 0.9),
            ambientColor: SIMD4<Float>(0, 0, 0, 0))
        renderEncoder.setFragmentBytes(
            &accumulationUniforms, length: MemoryLayout<RainUniforms>.stride, index: 1)
        if !accumulationVertices.isEmpty {
            accumulationVertices.withUnsafeBytes { bufferPointer in
                renderEncoder.setVertexBytes(
                    bufferPointer.baseAddress!,
                    length: accumulationVertices.count * MemoryLayout<Vertex>.stride,
                    index: 0)
            }
            renderEncoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: accumulationVertices.count)
        }
    }
}
