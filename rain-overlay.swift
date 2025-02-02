import Cocoa
import Metal
import MetalKit
import UniformTypeIdentifiers
import simd

// MARK: - RainSettings

struct RainSettings: Codable {
    var numberOfDrops: Int
    var speed: Float  // Base speed for raindrops
    var angle: Float  // In degrees; positive means rain comes from the left.
    var color: NSColor
    var length: Float  // Base length for raindrops (short drops)
    var smearFactor: Float  // Multiplier for the trailing smear
    var splashIntensity: Float  // Multiplier for splash effect (e.g. 0.3 means 30% intensity)

    enum CodingKeys: String, CodingKey {
        case numberOfDrops, speed, angle, color, length, smearFactor, splashIntensity
    }

    // NSColor isn’t directly Codable – we encode its RGBA components.
    struct ColorComponents: Codable {
        var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    }

    init(
        numberOfDrops: Int, speed: Float, angle: Float, color: NSColor, length: Float,
        smearFactor: Float, splashIntensity: Float
    ) {
        self.numberOfDrops = numberOfDrops
        self.speed = speed
        self.angle = angle
        self.color = color
        self.length = length
        self.smearFactor = smearFactor
        self.splashIntensity = splashIntensity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        numberOfDrops = try container.decode(Int.self, forKey: .numberOfDrops)
        speed = try container.decode(Float.self, forKey: .speed)
        angle = try container.decode(Float.self, forKey: .angle)
        length = try container.decode(Float.self, forKey: .length)
        smearFactor = try container.decode(Float.self, forKey: .smearFactor)
        splashIntensity = try container.decode(Float.self, forKey: .splashIntensity)
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

// MARK: - Vertex Structure

struct Vertex {
    var position: SIMD2<Float>
    var alpha: Float
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var rainView: RainView!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBarItem()

        let screen = NSScreen.main!
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.hasShadow = false
        window.alphaValue = 1.0
        window.backgroundColor = NSColor.clear

        if let device = MTLCreateSystemDefaultDevice() {
            // Default settings:
            // 200 drops, speed 0.01, angle 30° (rain from left),
            // white color, drop length 0.05, smearFactor 4.0,
            // splashIntensity 0.3 (i.e. 30% of full splash effect).
            let defaultSettings = RainSettings(
                numberOfDrops: 200,
                speed: 0.01,
                angle: 30.0,
                color: NSColor.white,
                length: 0.05,
                smearFactor: 4.0,
                splashIntensity: 0.3
            )
            rainView = RainView(
                frame: window.contentView!.bounds, device: device, settings: defaultSettings)
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
                title: "Increase Drops", action: #selector(increaseDrops), keyEquivalent: "i"))
        menu.addItem(
            NSMenuItem(
                title: "Decrease Drops", action: #selector(decreaseDrops), keyEquivalent: "d"))
        menu.addItem(
            NSMenuItem(
                title: "Increase Speed", action: #selector(increaseSpeed), keyEquivalent: "s"))
        menu.addItem(
            NSMenuItem(
                title: "Decrease Speed", action: #selector(decreaseSpeed), keyEquivalent: "a"))
        menu.addItem(
            NSMenuItem(
                title: "Increase Angle", action: #selector(increaseAngle), keyEquivalent: "g"))
        menu.addItem(
            NSMenuItem(
                title: "Decrease Angle", action: #selector(decreaseAngle), keyEquivalent: "h"))
        menu.addItem(
            NSMenuItem(
                title: "Increase Length", action: #selector(increaseLength), keyEquivalent: "l"))
        menu.addItem(
            NSMenuItem(
                title: "Decrease Length", action: #selector(decreaseLength), keyEquivalent: "k"))
        menu.addItem(
            NSMenuItem(title: "Change Color", action: #selector(changeColor), keyEquivalent: "c"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Save Config", action: #selector(saveConfig), keyEquivalent: "o"))
        menu.addItem(
            NSMenuItem(title: "Load Config", action: #selector(loadConfig), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleMenu(_ sender: Any?) {
        if let button = statusItem.button {
            statusItem.menu?.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height),
                in: button)
        }
    }

    // MARK: - Rain Settings Actions

    @objc func increaseDrops() {
        rainView.settings.numberOfDrops += 50
        rainView.createRaindrops()
    }

    @objc func decreaseDrops() {
        rainView.settings.numberOfDrops = max(0, rainView.settings.numberOfDrops - 50)
        rainView.createRaindrops()
    }

    @objc func increaseSpeed() {
        rainView.settings.speed += 0.002
    }

    @objc func decreaseSpeed() {
        rainView.settings.speed = max(0.002, rainView.settings.speed - 0.002)
    }

    @objc func increaseAngle() {
        rainView.settings.angle = min(85.0, rainView.settings.angle + 5)
        rainView.createRaindrops()
    }

    @objc func decreaseAngle() {
        rainView.settings.angle = max(-85.0, rainView.settings.angle - 5)
        rainView.createRaindrops()
    }

    @objc func increaseLength() {
        rainView.settings.length += 0.005
    }

    @objc func decreaseLength() {
        rainView.settings.length = max(0.005, rainView.settings.length - 0.005)
    }

    @objc func changeColor() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func colorDidChange(_ sender: NSColorPanel) {
        rainView.settings.color = sender.color
    }

    @objc func saveConfig() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.json]
        savePanel.nameFieldStringValue = "rainConfig.json"
        savePanel.begin { [weak self] response in
            if response == .OK, let url = savePanel.url {
                self?.writeConfig(to: url)
            }
        }
    }

    func writeConfig(to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(rainView.settings)
            try data.write(to: url)
            print("Config saved to \(url.path)")
        } catch {
            print("Failed to save config: \(error)")
        }
    }

    @objc func loadConfig() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.begin { [weak self] response in
            if response == .OK, let url = openPanel.url {
                self?.readConfig(from: url)
            }
        }
    }

    func readConfig(from url: URL) {
        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: url)
            let newSettings = try decoder.decode(RainSettings.self, from: data)
            rainView.settings = newSettings
            rainView.createRaindrops()
            print("Config loaded from \(url.path)")
        } catch {
            print("Failed to load config: \(error)")
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
}

// MARK: - RainView

class RainView: MTKView {

    var settings: RainSettings

    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!

    private var raindrops: [Raindrop] = []
    private var splashes: [Splash] = []

    // Compute current rain angle (in radians) from settings.angle.
    private var currentAngle: Float {
        return settings.angle * .pi / 180.0
    }

    // MARK: - Types

    struct Raindrop {
        var position: SIMD2<Float>
        var speed: Float
        var length: Float
    }

    // Splash particles using physics.
    struct Splash {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var life: Float  // current life remaining
        var startLife: Float  // for alpha calculation

        mutating func update() {
            // dt ≈ 0.016 at 60fps.
            life -= 0.016
            velocity *= 0.99  // smoother drag
            velocity.y -= 0.003  // reduced gravity
            position += velocity
        }

        var alpha: Float {
            let norm = max(life / startLife, 0)
            return norm * norm  // squared fade-out
        }
    }

    // MARK: - Initializer

    init(frame frameRect: CGRect, device: MTLDevice, settings: RainSettings) {
        self.settings = settings
        super.init(frame: frameRect, device: device)

        self.commandQueue = device.makeCommandQueue()
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = false

        setupPipeline()
        createRaindrops()

        self.preferredFramesPerSecond = 60
        self.enableSetNeedsDisplay = true
        self.isPaused = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup Pipeline

    private func setupPipeline() {
        guard let device = self.device else { return }
        // Shader using per-vertex alpha.
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
            vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                                          const device Vertex *vertices [[buffer(0)]]) {
                VertexOut out;
                out.position = float4(vertices[vertexID].position, 0.0, 1.0);
                out.alpha = vertices[vertexID].alpha;
                return out;
            }
            fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
                return float4(0.7, 0.7, 1.0, in.alpha * 0.3);
            }
            """
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

    // MARK: - Create Raindrops

    func createRaindrops() {
        raindrops.removeAll()
        // Distribute drops from the top and the side (depending on angle).
        for _ in 0..<settings.numberOfDrops {
            let source: String
            if settings.angle > 0 {
                // 50% chance top, 50% chance left.
                source = Bool.random() ? "top" : "side"
            } else if settings.angle < 0 {
                source = Bool.random() ? "top" : "side"
            } else {
                source = "top"
            }
            let initialX: Float
            let initialY: Float
            if source == "top" {
                // From top: y is exactly 1, x spans entire width.
                initialX = Float.random(in: -1...1)
                initialY = 1
            } else {  // "side"
                // From side: if angle > 0, left edge; if angle < 0, right edge.
                if settings.angle > 0 {
                    initialX = -1
                } else if settings.angle < 0 {
                    initialX = 1
                } else {
                    initialX = Float.random(in: -1...1)
                }
                // y is randomized over [0,1] so drops start in the upper half.
                initialY = Float.random(in: 0...1)
            }
            let drop = Raindrop(
                position: SIMD2<Float>(initialX, initialY),
                speed: Float.random(in: settings.speed...(settings.speed * 2)),
                length: Float.random(in: settings.length...(settings.length * 2))
            )
            raindrops.append(drop)
        }
    }

    // MARK: - Create Splash Particles

    private func createSplash(at position: SIMD2<Float>) {
        // Create splashes when a drop hits the bottom.
        let count = Int.random(in: 3...5)
        for _ in 0..<count {
            let randomAngle = Float.random(in: (Float.pi / 6)...(5 * Float.pi / 6))
            let speed = Float.random(in: 0.01...0.02)
            let vel = SIMD2<Float>(
                cos(randomAngle) * speed,
                sin(randomAngle) * speed * 2.5  // enhanced vertical movement
            )
            let life = Float.random(in: 0.4...0.8)
            let splash = Splash(position: position, velocity: vel, life: life, startLife: life)
            splashes.append(splash)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = currentRenderPassDescriptor,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        // Build vertex arrays for raindrops and splashes.
        var raindropVertices: [Vertex] = []
        var splashVertices: [Vertex] = []

        // --- Update and Render Raindrops ---
        for i in 0..<raindrops.count {
            // Update drop position.
            let dx = sin(currentAngle) * raindrops[i].speed
            let dy = -cos(currentAngle) * raindrops[i].speed
            raindrops[i].position.x += dx
            raindrops[i].position.y += dy

            // If a drop falls below -1 (bottom), create a splash and reset it.
            if raindrops[i].position.y < -1 {
                createSplash(at: raindrops[i].position)
                // Reset drop: choose new source based on angle.
                let source: String
                if settings.angle > 0 {
                    source = Bool.random() ? "top" : "side"
                } else if settings.angle < 0 {
                    source = Bool.random() ? "top" : "side"
                } else {
                    source = "top"
                }
                let newX: Float
                let newY: Float
                if source == "top" {
                    newX = Float.random(in: -1...1)
                    newY = 1
                } else {  // side
                    if settings.angle > 0 {
                        newX = -1
                    } else if settings.angle < 0 {
                        newX = 1
                    } else {
                        newX = Float.random(in: -1...1)
                    }
                    newY = Float.random(in: 0...1)
                }
                raindrops[i].position = SIMD2<Float>(newX, newY)
            }

            let dropDir = SIMD2<Float>(sin(currentAngle), -cos(currentAngle))
            let dropLength = raindrops[i].length * 0.5  // much shorter drops
            let dropEnd = raindrops[i].position + dropDir * dropLength
            // Add drop vertices (full opacity).
            raindropVertices.append(Vertex(position: raindrops[i].position, alpha: 1.0))
            raindropVertices.append(Vertex(position: dropEnd, alpha: 1.0))
            // Trailing smear.
            let smearLength = raindrops[i].length * settings.smearFactor
            let smearEnd = raindrops[i].position + dropDir * smearLength
            raindropVertices.append(Vertex(position: raindrops[i].position, alpha: 0.3))
            raindropVertices.append(Vertex(position: smearEnd, alpha: 0.3))
        }

        // --- Update and Render Splashes ---
        for i in 0..<splashes.count {
            splashes[i].update()
        }
        splashes = splashes.filter { $0.life > 0 }
        for splash in splashes {
            let v = splash.velocity
            let mag = simd_length(v)
            let offset: SIMD2<Float>
            if mag > 0.0001 {
                offset = (v / mag) * (0.08 * settings.splashIntensity)
            } else {
                offset = SIMD2<Float>(
                    0.08 * settings.splashIntensity, 0.08 * settings.splashIntensity)
            }
            let start = splash.position
            let end = splash.position + offset
            let a = splash.alpha * settings.splashIntensity
            splashVertices.append(Vertex(position: start, alpha: a))
            splashVertices.append(Vertex(position: end, alpha: a))
        }

        // --- Draw Raindrops ---
        raindropVertices.withUnsafeBytes { bufferPointer in
            renderEncoder.setVertexBytes(
                bufferPointer.baseAddress!,
                length: raindropVertices.count * MemoryLayout<Vertex>.stride,
                index: 0)
        }
        renderEncoder.drawPrimitives(
            type: .line, vertexStart: 0, vertexCount: raindropVertices.count)

        // --- Draw Splashes ---
        splashVertices.withUnsafeBytes { bufferPointer in
            renderEncoder.setVertexBytes(
                bufferPointer.baseAddress!,
                length: splashVertices.count * MemoryLayout<Vertex>.stride,
                index: 0)
        }
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: splashVertices.count)

        renderEncoder.endEncoding()
        if let drawable = currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
