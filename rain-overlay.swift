//
//  RainOverlay.swift
//  Example macOS SwiftUI app
//
//  This file implements a rain and snow overlay using Metal and SwiftUI.
//  It includes a settings UI, a custom Metal view (RainView) that simulates rain
//  and snow, and uses a fixed‐size pool allocated on the heap to manage snowflake state.
//
//  The snow simulation uses normalized device coordinates (NDC) in the range [-1, 1].
//  Snowflakes are created above the top (y > 1) and fall downward slowly. If not enough
//  active snowflakes are present, new ones will be spawned immediately.
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

/// A Codable structure representing the settings for rain (and snow) simulation.
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
    var snowAccumulationThreshold: Float

    enum CodingKeys: String, CodingKey {
        case numberOfDrops, speed, angle, color, length, smearFactor, splashIntensity, windEnabled,
            windIntensity, mouseEnabled, mouseInfluenceIntensity, maxFPS, rainEnabled, snowEnabled,
            snowAccumulationThreshold
    }

    /// Helper structure for encoding/decoding NSColor.
    struct ColorComponents: Codable {
        var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    }

    // MARK: - Initializers

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

/// A custom NSWindowController that hosts the settings view.
class SettingsWindowController: NSWindowController {
    var rainView: RainView

    init(rainView: RainView) {
        self.rainView = rainView
        let window = SettingsWindow(rainView: rainView)
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A custom NSWindow that uses a visual effect view to host the settings SwiftUI view.
class SettingsWindow: NSWindow {
    init(rainView: RainView) {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 650)
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

// MARK: - Neon Text View Modifier

/// A view modifier that applies a neon, flickering effect.
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

/// The SwiftUI view that presents rain and snow simulation settings.
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
                Button("Load from JSON") { loadFromJSON() }.fluorescentNeon()
                Button("Save to JSON") { saveToJSON() }.fluorescentNeon()
            }
            .padding(.top, 10)

            Spacer()

            HStack {
                Spacer()
                Button("Close") { closeSettingsWindow() }
                    .fluorescentNeon()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(
                            Color(nsColor: .windowBackgroundColor).opacity(0.5))
                    )
                    .padding([.bottom, .trailing], 10)
            }
        }
        .padding(30)
        .frame(width: 800, height: 650)
    }

    // MARK: - JSON Load/Save Helpers

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

// MARK: - NumericSettingRow & ToggleSettingRow

struct NumericSettingRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).fluorescentNeon()
            Slider(value: $value, in: range, step: step)
            Text(String(format: "%.4f", value))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8).fill(
                Color(nsColor: .windowBackgroundColor).opacity(0.5)))
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
            RoundedRectangle(cornerRadius: 8).fill(
                Color(nsColor: .windowBackgroundColor).opacity(0.5)))
    }
}

// MARK: - RainSettingsStore

/// An observable object that stores the current rain (and snow) settings,
/// and updates the associated RainView when properties change.
class RainSettingsStore: ObservableObject {
    private weak var rainView: RainView?

    @Published var numberOfDrops: Double {
        didSet { updateRainView { $0.numberOfDrops = Int(numberOfDrops) } }
    }
    @Published var speed: Double { didSet { updateRainView { $0.speed = Float(speed) } } }
    @Published var angle: Double { didSet { updateRainView { $0.angle = Float(angle) } } }
    @Published var length: Double { didSet { updateRainView { $0.length = Float(length) } } }
    @Published var color: Color {
        didSet { updateRainView { $0.color = NSColor(color) } }
    }
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

/// The application delegate sets up the status bar, the main window, and the rain view.
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

/// A structure representing a vertex with a 2D position and an alpha (opacity) value.
struct Vertex {
    var position: SIMD2<Float>
    var alpha: Float
}

// MARK: - Snowflake Structures

/// The basic data for a snowflake.
struct Snowflake {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var size: Float
    var wobblePhase: Float  // For side-to-side motion.
    var wobbleAmplitude: Float  // Magnitude of the wobble.
}

/// A structure that contains the snowflake along with its rendering state.
struct SnowflakeState {
    var flake: Snowflake
    var opacity: Float  // For fade-in/fade-out.
    var rotation: Float  // Rotation for drawing.
    var isActive: Bool  // Whether this slot is active.
}

// MARK: - RainView

/// A custom MTKView that renders rain and snow using Metal.
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

    // Snow accumulation (not used in this sample, but available).
    private var snowPiles: [Float] = []
    private let snowPileResolution: Int = 100

    // Ambient environment and wind.
    private var wind: Float = 0.0
    private var ambientColor: SIMD4<Float> = SIMD4<Float>(0.05, 0.05, 0.1, 1.0)
    private var time: Float = 0.0

    private var currentAngle: Float { settings.angle * .pi / 180.0 }

    // MARK: Fixed-Size Pool for Snowflakes

    /// The number of slots in the snowflake pool.
    private var _poolSize: Int = 200
    /// The heap-allocated pool of snowflake states.
    private var _snowflakePool: UnsafeMutableBufferPointer<SnowflakeState>?

    // MARK: - Structures for Rain

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

    /// Uniforms passed to the Metal shader.
    struct RainUniforms {
        var rainColor: SIMD4<Float>
        var ambientColor: SIMD4<Float>
    }

    // MARK: - Initialization

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

        // Initialize snow accumulation piles if needed.
        if settings.snowEnabled {
            snowPiles = Array(
                repeating: settings.snowAccumulationThreshold, count: snowPileResolution)
        }

        self.enableSetNeedsDisplay = true
        self.isPaused = false

        // Initialize the fixed-size snowflake pool.
        initializeSnowflakePool(with: _poolSize)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { destroySnowflakePool() }

    // MARK: - Metal Pipeline Setup

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

    // MARK: - Environment & Rain Updates

    /// Updates wind and ambient color over time.
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

    /// Creates raindrops according to the current settings.
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

    /// Determines a new spawn position for a raindrop in NDC.
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

    // MARK: - Fixed-Size Snowflake Pool Management

    /// Initializes the fixed-size pool for snowflakes with the given size.
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

    /// Reinitializes the pool to a new size.
    func reinitializeSnowflakePool(newSize: Int) { initializeSnowflakePool(with: newSize) }

    /// Finds the index of the first inactive (free) slot in the pool.
    func findFreeSlotInPool() -> Int? {
        guard let pool = _snowflakePool else { return nil }
        for i in 0..<pool.count {
            if !pool[i].isActive { return i }
        }
        return nil
    }

    /// Destroys (deallocates) the snowflake pool.
    func destroySnowflakePool() {
        if let pool = _snowflakePool {
            pool.baseAddress?.deinitialize(count: pool.count)
            pool.baseAddress?.deallocate()
            _snowflakePool = nil
        }
    }

    // MARK: - Snowflake Creation & Reset

    /// Creates a new snowflake in normalized coordinates.
    func createSnowflake() -> Snowflake {
        // Spawn x anywhere in [-1,1] and y slightly above the top (between 1.05 and 1.15).
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

    /// Clears (deactivates) all snowflakes and resets snow accumulation.
    func clearSnow() {
        if let pool = _snowflakePool {
            for i in 0..<pool.count {
                pool[i].isActive = false
            }
        }
        snowPiles = Array(repeating: settings.snowAccumulationThreshold, count: snowPileResolution)
    }

    /// Computes per-segment accumulation levels for snow based on window geometry.
    func computeWindowAccumulationLevels() -> [Float] {
        var levels = Array(repeating: settings.snowAccumulationThreshold, count: snowPileResolution)
        if let windowListInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        {
            let myWindowNumber = self.window?.windowNumber
            let screenHeight = NSScreen.main?.frame.height ?? 1.0
            let screenWidth = NSScreen.main?.frame.width ?? 1.0
            let offset = Float((30.0 / screenHeight) * 2)
            for info in windowListInfo {
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
                            levels[i] = max(levels[i], adjustedTop)
                        }
                    }
                }
            }
        }
        return levels
    }

    // MARK: - Draw Loop

    /// The main draw loop: updates environment, renders rain (and splashes) and snow.
    override func draw(_ dirtyRect: NSRect) {
        updateEnvironment()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = currentRenderPassDescriptor,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        // Set uniform parameters for rain.
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
                    // Respawn the drop.
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

        // Update and render splashes.
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

        // Draw raindrops.
        raindropVertices.withUnsafeBytes { bufferPointer in
            renderEncoder.setVertexBytes(
                bufferPointer.baseAddress!,
                length: raindropVertices.count * MemoryLayout<Vertex>.stride,
                index: 0)
        }
        renderEncoder.drawPrimitives(
            type: .line, vertexStart: 0, vertexCount: raindropVertices.count)
        // Draw splashes.
        splashVertices.withUnsafeBytes { bufferPointer in
            renderEncoder.setVertexBytes(
                bufferPointer.baseAddress!,
                length: splashVertices.count * MemoryLayout<Vertex>.stride,
                index: 0)
        }
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: splashVertices.count)

        // --- Snow Simulation ---
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

    /// A timestamp used to compute frame delta time.
    private var lastUpdateTime: CFTimeInterval = CACurrentMediaTime()

    /// Creates a splash effect at the given position.
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
    /// Converts an NSColor to a SIMD4<Float> (assumes deviceRGB color space).
    private func simd4(from color: NSColor) -> SIMD4<Float> {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return SIMD4<Float>(1, 1, 1, 1) }
        return SIMD4<Float>(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent),
            Float(rgb.alphaComponent))
    }

    /// Simulates and renders the snowfall effect using the fixed-size snowflake pool.
    ///
    /// - Parameters:
    ///   - deltaTime: The time elapsed since the last frame.
    ///   - renderEncoder: The Metal render command encoder used for drawing.
    func simulateAndRenderSnow(deltaTime: Float, renderEncoder: MTLRenderCommandEncoder) {
        guard let pool = _snowflakePool else { return }

        // Update each active snowflake.
        var activeCount = 0
        for i in 0..<pool.count {
            var state = pool[i]
            if !state.isActive { continue }
            activeCount += 1
            // Fade in and rotate.
            state.opacity = min(state.opacity + deltaTime * 2.0, 1.0)
            state.rotation += deltaTime * Float.random(in: 0.5...1.5)
            // Update wobble and position.
            state.flake.wobblePhase += deltaTime * 2.0
            let wobbleOffset = sin(state.flake.wobblePhase) * state.flake.wobbleAmplitude
            state.flake.position.x += state.flake.velocity.x + wobbleOffset
            state.flake.position.y += state.flake.velocity.y

            // Deactivate if the snowflake falls below the bottom.
            if state.flake.position.y < -1 { state.isActive = false }
            pool[i] = state
        }

        // Ensure a minimum number of active snowflakes.
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

        // Build the vertex list from active snowflakes.
        var snowflakeVertices: [Vertex] = []
        for i in 0..<pool.count {
            let state = pool[i]
            if !state.isActive { continue }
            let s = state.flake.size
            let x = state.flake.position.x
            let y = state.flake.position.y
            let rotation = state.rotation
            let opacity = state.opacity
            // Create a simple 6-line snowflake shape.
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

        // Draw snowflakes if any vertices exist.
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
    }
}
