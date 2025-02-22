//
//  RainOverlay.swift
//  Example macOS SwiftUI app
//
//  Demonstrates storing snow accumulation per window ID.
//  Each window has its own data, so if you move or resize the window,
//  its snow can follow it.
//
//  Added extra debug output (enabled with the "--debug" command‑line option)
//  to print screen dimensions and normalized coordinates. Segments whose normalized
//  Y coordinate is outside –1…+1 are flagged.
//
import ApplicationServices
import Cocoa
import Combine
import CoreGraphics
import Metal
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import simd

#if os(macOS)
    import CoreGraphics

    /// Returns whether the app has screen capture (screen recording) permission.
    func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Requests screen recording permission asynchronously.
    func requestScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            let granted = CGRequestScreenCaptureAccess()
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
#endif

// MARK: - Global Debug Flag

/// Global debug mode; set to true if the command‑line contains "--debug"
let DEBUG_MODE: Bool = CommandLine.arguments.contains("--debug")

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
    var rainEnabled: Bool
    var snowEnabled: Bool
    var snowAccumulationThreshold: Float
    var showWindowTops: Bool
    var accumulationRate: Float = 0.1  // Default to 10% of original rate

    enum CodingKeys: String, CodingKey {
        case numberOfDrops, speed, angle, color, length, smearFactor, splashIntensity,
            windEnabled, windIntensity, mouseEnabled, mouseInfluenceIntensity, maxFPS,
            rainEnabled, snowEnabled, snowAccumulationThreshold, showWindowTops, accumulationRate
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
        maxFPS: Int = 30,
        rainEnabled: Bool = true,
        snowEnabled: Bool = false,
        snowAccumulationThreshold: Float = -1.0,
        showWindowTops: Bool = true,
        accumulationRate: Float = 0.1
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
        self.showWindowTops = showWindowTops
        self.accumulationRate = accumulationRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        numberOfDrops = try c.decode(Int.self, forKey: .numberOfDrops)
        speed = try c.decode(Float.self, forKey: .speed)
        angle = try c.decode(Float.self, forKey: .angle)
        length = try c.decode(Float.self, forKey: .length)
        smearFactor = try c.decode(Float.self, forKey: .smearFactor)
        splashIntensity = try c.decode(Float.self, forKey: .splashIntensity)
        windEnabled = try c.decode(Bool.self, forKey: .windEnabled)
        windIntensity = try c.decode(Float.self, forKey: .windIntensity)
        mouseEnabled = try c.decode(Bool.self, forKey: .mouseEnabled)
        mouseInfluenceIntensity = try c.decode(Float.self, forKey: .mouseInfluenceIntensity)
        maxFPS = try c.decodeIfPresent(Int.self, forKey: .maxFPS) ?? 30
        rainEnabled = try c.decodeIfPresent(Bool.self, forKey: .rainEnabled) ?? true
        snowEnabled = try c.decodeIfPresent(Bool.self, forKey: .snowEnabled) ?? false
        snowAccumulationThreshold =
            try c.decodeIfPresent(Float.self, forKey: .snowAccumulationThreshold) ?? -1.0

        let comps = try c.decode(ColorComponents.self, forKey: .color)
        color = NSColor(
            calibratedRed: comps.red, green: comps.green, blue: comps.blue, alpha: comps.alpha)
        showWindowTops = try c.decodeIfPresent(Bool.self, forKey: .showWindowTops) ?? false
        accumulationRate = try c.decodeIfPresent(Float.self, forKey: .accumulationRate) ?? 0.1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(numberOfDrops, forKey: .numberOfDrops)
        try c.encode(speed, forKey: .speed)
        try c.encode(angle, forKey: .angle)
        try c.encode(length, forKey: .length)
        try c.encode(smearFactor, forKey: .smearFactor)
        try c.encode(splashIntensity, forKey: .splashIntensity)
        try c.encode(windEnabled, forKey: .windEnabled)
        try c.encode(windIntensity, forKey: .windIntensity)
        try c.encode(mouseEnabled, forKey: .mouseEnabled)
        try c.encode(mouseInfluenceIntensity, forKey: .mouseInfluenceIntensity)
        try c.encode(maxFPS, forKey: .maxFPS)
        try c.encode(rainEnabled, forKey: .rainEnabled)
        try c.encode(snowEnabled, forKey: .snowEnabled)
        try c.encode(snowAccumulationThreshold, forKey: .snowAccumulationThreshold)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if let rgb = color.usingColorSpace(.deviceRGB) {
            rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        let comps = ColorComponents(red: red, green: green, blue: blue, alpha: alpha)
        try c.encode(comps, forKey: .color)
        try c.encode(showWindowTops, forKey: .showWindowTops)
        try c.encode(accumulationRate, forKey: .accumulationRate)
    }
}

// MARK: - Settings Window

class SettingsWindowController: NSWindowController {
    var rainView: RainView
    init(rainView: RainView) {
        self.rainView = rainView
        let window = SettingsWindow(rainView: rainView)
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

class SettingsWindow: NSWindow {
    init(rainView: RainView) {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 650)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
            // [Other settings UI omitted for brevity]
            HStack(spacing: 20) {
                Button("Load from JSON") { loadFromJSON() }
                    .fluorescentNeon()
                Button("Save to JSON") { saveToJSON() }
                    .fluorescentNeon()
            }
            .padding(.top, 10)
            Spacer()
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
            .padding(.bottom, 20)
        }
        .padding(30)
        .frame(width: 800, height: settingsStore.snowEnabled ? 750 : 650)
    }

    private func loadFromJSON() {
        let panel = NSOpenPanel()
        // Use allowedContentTypes for macOS 12 and later
        panel.allowedContentTypes = [UTType.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let loadedSettings = try decoder.decode(RainSettings.self, from: data)
                // Update the settings store (and thus the rainView)
                settingsStore.updateFrom(loadedSettings)
            } catch {
                print("Error loading settings: \(error)")
            }
        }
    }

    private func saveToJSON() {
        let panel = NSSavePanel()
        // Use allowedContentTypes for macOS 12 and later
        panel.allowedContentTypes = [UTType.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(settingsStore.currentSettings)
                try data.write(to: url)
            } catch {
                print("Error saving settings: \(error)")
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
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
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
            if let view = rainView {
                view.settings.snowEnabled = snowEnabled
                view.resetSnowSystem()
            }
        }
    }
    @Published var snowAccumulationThreshold: Double {
        didSet {
            updateRainView { $0.snowAccumulationThreshold = Float(snowAccumulationThreshold) }
        }
    }
    @Published var showWindowTops: Bool {
        didSet { updateRainView { $0.showWindowTops = showWindowTops } }
    }

    init(rainView: RainView?) {
        self.rainView = rainView
        let s =
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
                snowEnabled: true,
                snowAccumulationThreshold: -1.0,
                showWindowTops: true
            )
        numberOfDrops = Double(s.numberOfDrops)
        speed = Double(s.speed)
        angle = Double(s.angle)
        length = Double(s.length)
        color = Color(s.color)
        windEnabled = s.windEnabled
        windIntensity = Double(s.windIntensity)
        mouseEnabled = s.mouseEnabled
        mouseInfluenceIntensity = Double(s.mouseInfluenceIntensity)
        rainEnabled = s.rainEnabled
        snowEnabled = s.snowEnabled
        snowAccumulationThreshold = Double(s.snowAccumulationThreshold)
        showWindowTops = s.showWindowTops
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
            snowAccumulationThreshold: Float(snowAccumulationThreshold),
            showWindowTops: showWindowTops
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
        showWindowTops = newSettings.showWindowTops
    }

    private func updateRainView(_ update: (inout RainSettings) -> Void) {
        guard let rv = rainView else { return }
        var s = rv.settings
        update(&s)
        rv.settings = s
        rv.createRaindrops()
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
        #if os(macOS)
            if !hasScreenRecordingPermission() {
                requestScreenRecordingPermission { granted in
                    if !granted {
                        let alert = NSAlert()
                        alert.messageText = "Screen Recording Permission Required"
                        alert.informativeText = """
                            This app needs screen recording permission in order to detect window positions
                            so that snow accumulates on top of application windows.
                            Please enable this in System Preferences → Security & Privacy → Privacy → Screen Recording.
                            """
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        #endif
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
                maxFPS: 30,
                rainEnabled: true,
                snowEnabled: true,
                snowAccumulationThreshold: -1.0,
                showWindowTops: true
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
            NSApp.activate(ignoringOtherApps: true)
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
            NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        )
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

struct Vertex {
    var position: SIMD2<Float>
    var alpha: Float
}

// MARK: - Snowflake

struct Snowflake {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var size: Float
    var wobblePhase: Float
    var wobbleAmplitude: Float
}

struct SnowflakeState {
    var flake: Snowflake
    var opacity: Float
    var rotation: Float
    var isActive: Bool
}

// MARK: - WindowSnow

/// Holds per-window snow data.
private struct WindowSnow {
    var windowID: Int
    var bounds: CGRect
    let resolution: Int
    var accumOffsets: [Float]
    var layer: Int  // already filtered to 0
    var zOrder: Int  // new property to capture actual z‑order

    init(windowID: Int, bounds: CGRect, resolution: Int, layer: Int, zOrder: Int) {
        self.windowID = windowID
        self.bounds = bounds
        self.resolution = resolution
        self.accumOffsets = [Float](repeating: 0.0, count: resolution)
        self.layer = layer
        self.zOrder = zOrder
    }
}

// MARK: - RainView

class RainView: MTKView {
    var settings: RainSettings {
        didSet { self.preferredFramesPerSecond = settings.maxFPS }
    }

    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!

    // Raindrops and splashes
    private var raindrops: [Raindrop] = []
    private var splashes: [Splash] = []

    // Per-window snow data
    private var windowSnowMap: [Int: WindowSnow] = [:]  // keyed by windowID
    private let snowResolution: Int = 60

    // Snowflake pool
    private var _poolSize: Int = 200
    private var _snowflakePool: UnsafeMutableBufferPointer<SnowflakeState>?

    // Environment
    private var wind: Float = 0.0
    private var ambientColor = SIMD4<Float>(0.05, 0.05, 0.1, 1.0)
    private var time: Float = 0.0
    private var lastUpdateTime: CFTimeInterval = CACurrentMediaTime()
    private var currentAngle: Float { settings.angle * .pi / 180.0 }

    // MARK: - Raindrop and Splash Types

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

    // MARK: - Debug Colors (for Snow/Window hitboxes)

    private var windowColorMap: [Int: Int] = [:]
    private let debugColors: [NSColor] = [
        .systemRed, .systemGreen, .systemBlue, .systemYellow, .systemPurple, .systemOrange,
    ]
    private func colorForWindowID(_ windowID: Int) -> NSColor {
        let idx = windowColorMap[windowID] ?? 0
        return debugColors[idx % debugColors.count]
    }
    private func cycleColor(forWindow windowID: Int) {
        let oldIndex = windowColorMap[windowID] ?? 0
        let newIndex = (oldIndex + 1) % debugColors.count
        windowColorMap[windowID] = newIndex
    }

    // MARK: - Helper: Check if a window is mostly visible
    private func isMostlyVisible(_ windowRect: CGRect, in screenRect: CGRect) -> Bool {
        let intersection = windowRect.intersection(screenRect)
        let areaVisible = intersection.width * intersection.height
        let areaWindow = windowRect.width * windowRect.height
        return areaWindow > 0 && (areaVisible / areaWindow) > 0.5
    }

    // MARK: - Initialization

    init(frame: CGRect, device: MTLDevice, settings: RainSettings) {
        self.settings = settings
        super.init(frame: frame, device: device)
        self.preferredFramesPerSecond = settings.maxFPS
        self.commandQueue = device.makeCommandQueue()
        self.clearColor = MTLClearColorMake(0, 0, 0, 0)
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = false
        setupPipeline()
        createRaindrops()
        initializeSnowflakePool(with: _poolSize)
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        if DEBUG_MODE {
            print("DEBUG: RainView initialized with frame: \(frame)")
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { destroySnowflakePool() }

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
            """
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFunction
            desc.fragmentFunction = fragmentFunction
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    // MARK: - Raindrops

    func createRaindrops() {
        raindrops.removeAll()
        if settings.rainEnabled {
            for _ in 0..<settings.numberOfDrops {
                let pos = newDropPosition()
                let special = Float.random(in: 0...1) < 0.01
                let lengthRange = settings.length * 0.5...settings.length * 2.0
                let rnd = Float.random(in: lengthRange)
                let normLen =
                    (rnd - lengthRange.lowerBound)
                    / (lengthRange.upperBound - lengthRange.lowerBound)
                let cInt = 0.4 + (normLen * 0.6)
                let drop = Raindrop(
                    position: pos,
                    speed: Float.random(in: settings.speed...(settings.speed * 2)),
                    length: rnd,
                    isSpecial: special,
                    colorIntensity: cInt
                )
                raindrops.append(drop)
            }
        }
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
            let x: Float =
                (settings.angle > 0)
                ? Float.random(in: -1 ... -0.8)
                : (settings.angle < 0 ? Float.random(in: 0.8...1) : Float.random(in: -1...1))
            let y = Float.random(in: -1...1)
            return SIMD2<Float>(x, y)
        }
    }

    func resetSnowSystem() {
        if settings.snowEnabled {
            initializeSnowflakePool(with: _poolSize)
            windowSnowMap.removeAll()
        } else {
            destroySnowflakePool()
            windowSnowMap.removeAll()
        }
    }

    // MARK: - Snowflake Pool

    func initializeSnowflakePool(with size: Int) {
        if let pool = _snowflakePool {
            pool.baseAddress?.deinitialize(count: pool.count)
            pool.baseAddress?.deallocate()
        }
        _poolSize = size
        let pointer = UnsafeMutablePointer<SnowflakeState>.allocate(capacity: size)
        for i in 0..<size {
            pointer.advanced(by: i).initialize(
                to: SnowflakeState(
                    flake: createSnowflake(),
                    opacity: 0.0,
                    rotation: Float.random(in: 0..<(2 * .pi)),
                    isActive: false
                )
            )
        }
        _snowflakePool = UnsafeMutableBufferPointer(start: pointer, count: size)
    }

    func destroySnowflakePool() {
        if let pool = _snowflakePool {
            pool.baseAddress?.deinitialize(count: pool.count)
            pool.baseAddress?.deallocate()
            _snowflakePool = nil
        }
    }

    // MARK: - Snowflake Creation

    func createSnowflake() -> Snowflake {
        guard let screen = NSScreen.main else {
            // Fallback values if screen isn’t available
            return Snowflake(
                position: SIMD2<Float>(0, 1),
                velocity: SIMD2<Float>(0, -0.01),
                size: 0.015,
                wobblePhase: 0,
                wobbleAmplitude: 0.001
            )
        }

        let screenW = Float(screen.frame.width)  // e.g., 3360
        //let screenH = Float(screen.frame.height)  // e.g., 1890

        // a. Slower fall speed: gentler descent
        let vy = -Float.random(in: 0.002...0.006)  // Was 0.005...0.015

        // b. Smaller, screen-scaled size
        let baseSize = screenW / 3360.0  // Normalize to a reference width (3360)
        let size = Float.random(in: 0.005...0.012) * baseSize  // Scaled, smaller range

        // c. Delightful touches
        let x = Float.random(in: -1.0...1.0)  // Full width spawn (already good)
        let vx = Float.random(in: -0.002...0.002)  // Slight horizontal drift
        let wobblePhase = Float.random(in: 0..<(2 * .pi))
        let wobbleAmplitude = Float.random(in: 0.0008...0.002) * baseSize  // Scaled wobble

        if DEBUG_MODE {
            print("DEBUG: Creating snowflake at (x: \(x), y: 0.9...1.1), size=\(size), vy=\(vy)")
        }

        return Snowflake(
            position: SIMD2<Float>(x, Float.random(in: 0.9...1.1)),  // Above or at top
            velocity: SIMD2<Float>(vx, vy),
            size: size,
            wobblePhase: wobblePhase,
            wobbleAmplitude: wobbleAmplitude
        )
    }

    // MARK: - Window Snow Map Update
    private func refreshWindowSnowMap() {
        guard let screen = NSScreen.main,
            let windowListInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return }

        let screenH = screen.frame.height
        let myWindowNum = self.window?.windowNumber
        var newWindowSnowMap: [Int: WindowSnow] = [:]

        // Local counter to assign zOrder only for filtered windows.
        var zOrderCounter = 0

        for info in windowListInfo {
            if let owner = info[kCGWindowOwnerName as String] as? String,
                owner == "Dock" || owner == "Window Server"
            {
                continue
            }
            guard let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,  // Keep filtering to layer 0 windows
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                windowNumber != myWindowNum,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let x = boundsDict["X"] as? CGFloat,
                let y = boundsDict["Y"] as? CGFloat,
                let w = boundsDict["Width"] as? CGFloat,
                let h = boundsDict["Height"] as? CGFloat
            else { continue }

            let cocoaY = screenH - y - h
            let rect = CGRect(x: x, y: cocoaY, width: w, height: h)

            // Reuse existing WindowSnow if unchanged.
            if let existingSnow = windowSnowMap[windowNumber],
                existingSnow.bounds == rect && existingSnow.layer == layer
            {
                newWindowSnowMap[windowNumber] = existingSnow
                if DEBUG_MODE {
                    print(
                        "DEBUG: Reusing WindowSnow for window \(windowNumber) with zOrder \(existingSnow.zOrder), bounds: \(rect)"
                    )
                }
            } else {
                let newSnow = WindowSnow(
                    windowID: windowNumber, bounds: rect, resolution: snowResolution, layer: layer,
                    zOrder: zOrderCounter)
                newWindowSnowMap[windowNumber] = newSnow
                if DEBUG_MODE {
                    print(
                        "DEBUG: New WindowSnow for window \(windowNumber) with zOrder \(zOrderCounter), bounds: \(rect)"
                    )
                }
            }
            zOrderCounter += 1
        }

        windowSnowMap = newWindowSnowMap

        if DEBUG_MODE {
            print("DEBUG: Refreshed window nodes. Count: \(windowSnowMap.count)")
            for (_, ws) in windowSnowMap {
                print("DEBUG: Window \(ws.windowID) - zOrder: \(ws.zOrder), bounds: \(ws.bounds)")
            }
        }
    }

    // MARK: - Simulate and Render Snow by Window
    func simulateAndRenderSnowByWindow(deltaTime: Float, renderEncoder: MTLRenderCommandEncoder) {
        guard let pool: UnsafeMutableBufferPointer<SnowflakeState> = _snowflakePool,
            let screen = NSScreen.main
        else { return }
        let screenW = Float(screen.frame.width)
        let screenH = Float(screen.frame.height)
        if DEBUG_MODE {
            print("DEBUG: Screen dimensions: width=\(screenW), height=\(screenH)")
        }
        let targetFlakes = 30
        var activeCount = 0

        // Process each snowflake
        for i in 0..<pool.count {
            var st = pool[i]
            if st.isActive {
                activeCount += 1
                st.opacity = min(st.opacity + deltaTime * 2.0, 1.0)
                st.rotation += deltaTime * Float.random(in: 0.5...1.5)
                st.flake.wobblePhase += deltaTime * 2.0
                let wobble = sin(st.flake.wobblePhase) * st.flake.wobbleAmplitude
                st.flake.position.x += st.flake.velocity.x + wobble
                st.flake.position.y += st.flake.velocity.y

                // Convert normalized snowflake position to screen coordinates (Cocoa)
                let flakeScreenX = (st.flake.position.x + 1) * 0.5 * screenW
                let flakeScreenY = (st.flake.position.y + 1) * 0.5 * screenH
                if DEBUG_MODE {
                    print("DEBUG: Snowflake \(i) at (x: \(flakeScreenX), y: \(flakeScreenY))")
                }

                // Check collision against windows in z-order (frontmost first)
                let sortedWindows = windowSnowMap.sorted { $0.value.layer < $1.value.layer }
                if DEBUG_MODE {
                    print("DEBUG: Sorted window order for collision detection:")
                    for (winID, wSnow) in sortedWindows {
                        print("    Window \(winID): zOrder \(wSnow.zOrder), bounds \(wSnow.bounds)")
                    }
                }
                var collisionOccurred = false
                for (winID, wSnow) in sortedWindows {
                    let wb = wSnow.bounds
                    if flakeScreenX >= Float(wb.origin.x)
                        && flakeScreenX <= Float(wb.origin.x + wb.width)
                    {
                        let windowTopY = Float(wb.origin.y + wb.height)
                        let fraction = (flakeScreenX - Float(wb.origin.x)) / Float(wb.width)
                        let segIndex = max(
                            0, min(wSnow.resolution - 1, Int(fraction * Float(wSnow.resolution))))
                        let currentSnowOffset = wSnow.accumOffsets[segIndex]
                        let segScreenYTop = windowTopY + currentSnowOffset
                        let collisionRangeMax = segScreenYTop + st.flake.size * 2.0 * (screenH / 2)
                        if DEBUG_MODE {
                            print(
                                "DEBUG: Window \(winID) seg \(segIndex): segScreenX=\(flakeScreenX), windowTop=\(windowTopY), accum=\(currentSnowOffset), range=\(windowTopY) to \(collisionRangeMax)"
                            )
                        }
                        // Collision check
                        if flakeScreenY >= windowTopY && flakeScreenY <= collisionRangeMax {
                            if DEBUG_MODE {
                                cycleColor(forWindow: winID)
                                print(
                                    "DEBUG: Snowflake \(i) collided with window \(winID) at seg \(segIndex) (flakeY=\(flakeScreenY))"
                                )
                            }
                            let accumulationRate = settings.accumulationRate
                            let growth = st.flake.size * 0.5 * (screenH / 2) * accumulationRate
                            if DEBUG_MODE {
                                print(
                                    "DEBUG: Applying growth=\(growth) to window \(winID) seg \(segIndex)"
                                )
                            }
                            windowSnowMap[winID]?.accumOffsets[segIndex] += growth
                            st.isActive = false
                            collisionOccurred = true
                            break  // Stop at the frontmost window
                        } else if DEBUG_MODE {
                            print(
                                "DEBUG: No collision for snowflake \(i) with window \(winID): flakeY=\(flakeScreenY) not in range \(windowTopY) to \(collisionRangeMax)"
                            )
                        }
                    }
                }
                // Deactivate snowflakes that fall off-screen
                if !collisionOccurred && (flakeScreenY < 0 || flakeScreenY > screenH + 50) {
                    st.isActive = false
                    if DEBUG_MODE {
                        print("DEBUG: Snowflake \(i) deactivated (off-screen)")
                    }
                }
            }
            pool[i] = st
        }

        // Spawn new snowflakes if below target
        if activeCount < targetFlakes {
            for i in 0..<pool.count where activeCount < targetFlakes {
                if !pool[i].isActive {
                    pool[i] = SnowflakeState(
                        flake: createSnowflake(),
                        opacity: 0.0,
                        rotation: Float.random(in: 0..<(2 * .pi)),
                        isActive: true
                    )
                    activeCount += 1
                }
            }
        }

        // Render snowflakes
        var snowflakeVerts: [Vertex] = []
        for i in 0..<pool.count {
            let st2 = pool[i]
            if !st2.isActive { continue }
            let s = st2.flake.size
            let x = st2.flake.position.x
            let y = st2.flake.position.y
            let rot = st2.rotation
            let op = st2.opacity
            for j in 0..<6 {
                let angle = rot + Float(j) * (.pi / 3)
                let sx = x + cos(angle) * (s * 0.5)
                let sy = y + sin(angle) * (s * 0.5)
                let ex = x - cos(angle) * (s * 0.5)
                let ey = y - sin(angle) * (s * 0.5)
                snowflakeVerts.append(Vertex(position: SIMD2<Float>(sx, sy), alpha: op))
                snowflakeVerts.append(Vertex(position: SIMD2<Float>(ex, ey), alpha: op))
            }
        }
        if !snowflakeVerts.isEmpty {
            snowflakeVerts.withUnsafeBytes { buf in
                renderEncoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: 0)
            }
            renderEncoder.drawPrimitives(
                type: .line, vertexStart: 0, vertexCount: snowflakeVerts.count)
        }

        // Draw accumulated snow
        drawAccumulatedSnow(
            renderEncoder: renderEncoder, screenW: screenW, screenH: screenH,
            screenFrame: screen.frame)
    }
    // MARK: - Drawing Accumulated Snow
    private func drawAccumulatedSnow(
        renderEncoder: MTLRenderCommandEncoder, screenW: Float, screenH: Float, screenFrame: CGRect
    ) {
        for (winID, wSnow) in windowSnowMap {
            let col: SIMD4<Float>
            if DEBUG_MODE && settings.showWindowTops {
                col = simd4(from: colorForWindowID(winID))
            } else {
                col = simd4(from: settings.color)
            }
            var debugUniforms = RainUniforms(rainColor: col, ambientColor: SIMD4<Float>(0, 0, 0, 0))
            renderEncoder.setFragmentBytes(
                &debugUniforms, length: MemoryLayout<RainUniforms>.stride, index: 1)

            let wb = wSnow.bounds
            let windowTopY = Float(wb.origin.y + wb.height)
            let leftX = Float(wb.origin.x)
            let rightX = Float(wb.origin.x + wb.width)
            var verts: [Vertex] = []
            for i in 0..<wSnow.resolution {
                let frac = Float(i) / Float(wSnow.resolution - 1)
                let segScreenX = leftX + frac * (rightX - leftX)
                let accum = wSnow.accumOffsets[i]
                let segScreenYTop = windowTopY + accum
                let normX = (segScreenX / screenW) * 2.0 - 1.0
                let normYTop = (segScreenYTop / screenH) * 2.0 - 1.0
                let normWindowTop = (windowTopY / screenH) * 2.0 - 1.0
                verts.append(Vertex(position: SIMD2<Float>(normX, normYTop), alpha: 0.9))
                verts.append(Vertex(position: SIMD2<Float>(normX, normWindowTop), alpha: 0.9))
                if DEBUG_MODE {
                    print(
                        "DEBUG: Window \(winID) seg \(i): segScreenX=\(segScreenX), windowTop=\(windowTopY), accum=\(accum), normYTop=\(normYTop)"
                    )
                }
            }
            if !verts.isEmpty {
                verts.withUnsafeBytes { buf in
                    renderEncoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: 0)
                }
                renderEncoder.drawPrimitives(
                    type: .triangleStrip, vertexStart: 0, vertexCount: verts.count)
            }
        }
        if settings.showWindowTops && DEBUG_MODE {
            drawVisibleWindowTopsDebug(renderEncoder: renderEncoder)
        }
    }

    private func drawVisibleWindowTopsDebug(renderEncoder: MTLRenderCommandEncoder) {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.frame
        let screenW = screenRect.width
        let screenH = screenRect.height
        for (winID, wSnow) in windowSnowMap {
            if !isMostlyVisible(wSnow.bounds, in: screenRect) { continue }
            let col = simd4(from: colorForWindowID(winID))
            var debugUniforms = RainUniforms(rainColor: col, ambientColor: SIMD4<Float>(0, 0, 0, 0))
            renderEncoder.setFragmentBytes(
                &debugUniforms, length: MemoryLayout<RainUniforms>.stride, index: 1)
            let wb = wSnow.bounds
            let windowTopY = Float(wb.origin.y + wb.height)
            let leftX = Float(wb.origin.x)
            let rightX = Float(wb.origin.x + wb.width)
            let normTop = (windowTopY / Float(screenH)) * 2.0 - 1.0
            let normLeft = (leftX / Float(screenW)) * 2.0 - 1.0
            let normRight = (rightX / Float(screenW)) * 2.0 - 1.0
            var lineVerts: [Vertex] = []
            lineVerts.append(Vertex(position: SIMD2<Float>(normLeft, normTop), alpha: 1.0))
            lineVerts.append(Vertex(position: SIMD2<Float>(normRight, normTop), alpha: 1.0))
            if DEBUG_MODE {
                print(
                    "DEBUG: Drawing hitbox for window \(winID): normLeft=\(normLeft), normTop=\(normTop), normRight=\(normRight)"
                )
            }
            lineVerts.withUnsafeBytes { buf in
                renderEncoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: 0)
            }
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lineVerts.count)
        }
    }

    // MARK: - Utility: NSColor to SIMD4<Float>
    private func simd4(from color: NSColor) -> SIMD4<Float> {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return SIMD4<Float>(1, 1, 1, 1)
        }
        return SIMD4<Float>(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent),
            Float(rgb.alphaComponent)
        )
    }

    // MARK: - Update Environment
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

    // MARK: - Create Splash
    private func createSplash(at pos: SIMD2<Float>, intensity: Float) {
        let count = Int.random(in: 3...5)
        for _ in 0..<count {
            let angle = Float.random(in: (Float.pi / 6)...(5 * Float.pi / 6))
            let speed = Float.random(in: 0.012...0.024)
            let vel = SIMD2<Float>(cos(angle) * speed, sin(angle) * speed * 3.0)
            let life = Float.random(in: 0.4...0.8)
            let sp = Splash(
                position: pos,
                velocity: vel,
                life: life,
                startLife: life,
                intensity: intensity
            )
            splashes.append(sp)
            if DEBUG_MODE {
                print("DEBUG: Created splash at \(pos) with intensity \(intensity)")
            }
        }
    }

    // MARK: - Draw
    override func draw(_ dirtyRect: NSRect) {
        if DEBUG_MODE {
            print(
                "DEBUG: Drawing frame at \(CACurrentMediaTime()). Raindrops count: \(raindrops.count)"
            )
        }
        refreshWindowSnowMap()
        updateEnvironment()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = currentRenderPassDescriptor,
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        encoder.setRenderPipelineState(pipelineState)
        var uniforms = RainUniforms(
            rainColor: simd4(from: settings.color),
            ambientColor: ambientColor
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RainUniforms>.stride, index: 1)

        // Process raindrops and splashes.
        var raindropVertices: [Vertex] = []
        var splashVertices: [Vertex] = []
        if settings.rainEnabled {
            for i in 0..<raindrops.count {
                let effSpeed =
                    raindrops[i].isSpecial ? raindrops[i].speed * 0.5 : raindrops[i].speed
                var dx = sin(currentAngle) * effSpeed + wind
                let dy = -cos(currentAngle) * effSpeed
                if settings.mouseEnabled {
                    let globalMouse = NSEvent.mouseLocation
                    if let screen = NSScreen.main {
                        let frame = screen.frame
                        let normX = ((globalMouse.x - frame.origin.x) / frame.width) * 2 - 1
                        let mousePos = SIMD2<Float>(Float(normX), 0)
                        let diff = mousePos - raindrops[i].position
                        let influence = diff * settings.mouseInfluenceIntensity
                        dx += influence.x
                    }
                }
                raindrops[i].position.x += dx
                raindrops[i].position.y += dy
                if raindrops[i].position.y < -1 {
                    if raindrops[i].colorIntensity > 0.85 {
                        self.createSplash(
                            at: raindrops[i].position, intensity: raindrops[i].colorIntensity)
                    }
                    let pos = newDropPosition()
                    let special = Float.random(in: 0...1) < 0.01
                    let lr = settings.length * 0.5...settings.length * 2.0
                    let rnd = Float.random(in: lr)
                    let normLen = (rnd - lr.lowerBound) / (lr.upperBound - lr.lowerBound)
                    let cInt = 0.4 + (normLen * 0.6)
                    raindrops[i].position = pos
                    raindrops[i].isSpecial = special
                    raindrops[i].length = rnd
                    raindrops[i].colorIntensity = cInt
                }
                let dropDir = SIMD2<Float>(sin(currentAngle), -cos(currentAngle))
                let dropLen = raindrops[i].length * 0.5
                let dropEnd = raindrops[i].position + dropDir * dropLen
                let dropAlpha = raindrops[i].colorIntensity
                raindropVertices.append(Vertex(position: raindrops[i].position, alpha: dropAlpha))
                raindropVertices.append(Vertex(position: dropEnd, alpha: dropAlpha))
                if raindrops[i].isSpecial && raindrops[i].colorIntensity > 0.85 {
                    let smearLen = raindrops[i].length * settings.smearFactor
                    let smearEnd = raindrops[i].position + dropDir * smearLen
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
            let off =
                (mag > 0.0001)
                ? (v / mag) * (0.1 * settings.splashIntensity)
                : SIMD2<Float>(0.1 * settings.splashIntensity, 0.1 * settings.splashIntensity)
            let start = splash.position
            let end = splash.position + off
            let a = splash.alpha * settings.splashIntensity
            splashVertices.append(Vertex(position: start, alpha: a))
            splashVertices.append(Vertex(position: end, alpha: a))
        }
        raindropVertices.withUnsafeBytes { buf in
            encoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: 0)
        }
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: raindropVertices.count)
        splashVertices.withUnsafeBytes { buf in
            encoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: 0)
        }
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: splashVertices.count)

        if settings.snowEnabled {
            let now = CACurrentMediaTime()
            let dt = Float(now - lastUpdateTime)
            lastUpdateTime = now
            simulateAndRenderSnowByWindow(deltaTime: dt, renderEncoder: encoder)
        }

        encoder.endEncoding()
        if let drawable = currentDrawable { commandBuffer.present(drawable) }
        commandBuffer.commit()
    }

    // New helper function that encapsulates the debug logic.
    private func debugProcessSnowflake(
        at index: Int,
        pool: inout UnsafeMutableBufferPointer<SnowflakeState>,
        screenW: Float,
        screenH: Float,
        deltaTime dt: Float
    ) {
        var st = pool[index]

        if st.isActive {
            // Condition 3: Update snowflake's position and log movement.
            let previousPosition = st.flake.position
            st.flake.position.x += st.flake.velocity.x * dt
            st.flake.position.y += st.flake.velocity.y * dt
            if DEBUG_MODE {
                print(
                    "DEBUG: Snowflake \(index) moved from \(previousPosition) to \(st.flake.position) with velocity \(st.flake.velocity)"
                )
            }

            // Condition 2: Map normalized snowflake coordinates to screen coordinates.
            let flakeScreenX = (st.flake.position.x + 1) * 0.5 * screenW
            let flakeScreenY = (st.flake.position.y + 1) * 0.5 * screenH
            if DEBUG_MODE {
                print(
                    "DEBUG: Snowflake \(index) screen coordinates: (\(flakeScreenX), \(flakeScreenY))"
                )
            }

            // Condition 1 & 4: Collision detection for each window.
            for (winID, wSnow) in windowSnowMap {
                let wb = wSnow.bounds
                if flakeScreenX >= Float(wb.origin.x)
                    && flakeScreenX <= Float(wb.origin.x + wb.width)
                {
                    let windowTopY = Float(wb.origin.y + wb.height)
                    let fraction = (flakeScreenX - Float(wb.origin.x)) / Float(wb.width)
                    let segIndex = max(
                        0, min(wSnow.resolution - 1, Int(fraction * Float(wSnow.resolution))))
                    let currentSnowOffset = wSnow.accumOffsets[segIndex]
                    let segScreenYTop = windowTopY + currentSnowOffset
                    if DEBUG_MODE {
                        print("DEBUG: For window \(winID) seg \(segIndex):")
                        print(
                            "       windowTopY = \(windowTopY), currentSnowOffset = \(currentSnowOffset), segScreenYTop = \(segScreenYTop)"
                        )
                    }

                    let collisionRangeMin = windowTopY
                    let collisionRangeMax = windowTopY + currentSnowOffset + st.flake.size * 2.0
                    if flakeScreenY >= collisionRangeMin && flakeScreenY <= collisionRangeMax {
                        if DEBUG_MODE {
                            print(
                                "DEBUG: Collision detected for snowflake \(index) on window \(winID) seg \(segIndex)."
                            )
                            print(
                                "       flakeScreenY = \(flakeScreenY) is within range \(collisionRangeMin) to \(collisionRangeMax)."
                            )
                        }
                        cycleColor(forWindow: winID)
                        windowSnowMap[winID]?.accumOffsets[segIndex] += st.flake.size * 0.5
                        st.isActive = false
                        break  // Exit once collision is processed.
                    } else {
                        if DEBUG_MODE {
                            print(
                                "DEBUG: No collision for snowflake \(index) on window \(winID) seg \(segIndex)."
                            )
                            print(
                                "       flakeScreenY = \(flakeScreenY) is NOT within range \(collisionRangeMin) to \(collisionRangeMax)."
                            )
                        }
                    }
                }
            }
        }

        pool[index] = st  // Write back the updated state.
    }

    func debugSnowflakeScreenPosition(
        index: Int, flakeX: Float, flakeY: Float, screenWidth: Float, screenHeight: Float
    ) {
        if flakeX < 0 || flakeX > screenWidth || flakeY < 0 || flakeY > screenHeight {
            print(
                "DEBUG: Snowflake \(index) is off-screen: (x: \(flakeX), y: \(flakeY)) [Screen: 0–\(screenWidth), 0–\(screenHeight)]"
            )
        } else {
            print("DEBUG: Snowflake \(index) is on-screen: (x: \(flakeX), y: \(flakeY))")
        }
    }

    func computeScreenX(for snowflake: SnowflakeState, screenWidth: Float) -> Float {
        return snowflake.flake.position.x * screenWidth
    }

    func computeScreenY(for snowflake: SnowflakeState, screenHeight: Float) -> Float {
        return snowflake.flake.position.y * screenHeight
    }
}

// MARK: - App Entry Point
