import Cocoa
import Metal
import MetalKit
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
    var maxFPS: Int  // New property for limiting FPS

    enum CodingKeys: String, CodingKey {
        case numberOfDrops, speed, angle, color, length, smearFactor, splashIntensity, windEnabled,
            windIntensity, mouseEnabled, mouseInfluenceIntensity, maxFPS
    }

    struct ColorComponents: Codable {
        var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    }

    init(
        numberOfDrops: Int, speed: Float, angle: Float, color: NSColor, length: Float,
        smearFactor: Float, splashIntensity: Float, windEnabled: Bool, windIntensity: Float,
        mouseEnabled: Bool, mouseInfluenceIntensity: Float, maxFPS: Int = 30  // Default FPS
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
        maxFPS = try container.decodeIfPresent(Int.self, forKey: .maxFPS) ?? 30  // Default if not present
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

// MARK: - Uniforms

struct RainUniforms {
    var rainColor: SIMD4<Float>
    var ambientColor: SIMD4<Float>
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
            // 200 drops, speed 0.005 (slow), angle 30° (rain from left), white rain color,
            // drop length 0.05, smearFactor 4.0, splashIntensity 0.3,
            // wind enabled with a very gentle intensity (default 0.0001),
            // mouse influence disabled by default.
            let defaultSettings = RainSettings(
                numberOfDrops: 200,
                speed: 0.005,
                angle: 30.0,
                color: NSColor.white,
                length: 0.05,
                smearFactor: 4.0,
                splashIntensity: 0.3,
                windEnabled: true,
                windIntensity: 0.0001,
                mouseEnabled: false,
                mouseInfluenceIntensity: 0.001
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
        menu.addItem(
            NSMenuItem(title: "Toggle Wind", action: #selector(toggleWind), keyEquivalent: "w"))
        menu.addItem(
            NSMenuItem(
                title: "Increase Wind Intensity", action: #selector(increaseWindIntensity),
                keyEquivalent: "e"))
        menu.addItem(
            NSMenuItem(
                title: "Decrease Wind Intensity", action: #selector(decreaseWindIntensity),
                keyEquivalent: "f"))
        menu.addItem(
            NSMenuItem(
                title: "Toggle Mouse Influence", action: #selector(toggleMouseInfluence),
                keyEquivalent: "m"))
        menu.addItem(
            NSMenuItem(
                title: "Increase Mouse Influence", action: #selector(increaseMouseInfluence),
                keyEquivalent: "r"))
        menu.addItem(
            NSMenuItem(
                title: "Decrease Mouse Influence", action: #selector(decreaseMouseInfluence),
                keyEquivalent: "t"))
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

    @objc func toggleWind() {
        rainView.settings.windEnabled.toggle()
        print("Wind enabled: \(rainView.settings.windEnabled)")
    }

    @objc func increaseWindIntensity() {
        rainView.settings.windIntensity += 0.0001
        print("Wind intensity: \(rainView.settings.windIntensity)")
    }

    @objc func decreaseWindIntensity() {
        rainView.settings.windIntensity = max(0.00005, rainView.settings.windIntensity - 0.0001)
        print("Wind intensity: \(rainView.settings.windIntensity)")
    }

    @objc func toggleMouseInfluence() {
        rainView.settings.mouseEnabled.toggle()
        print("Mouse influence enabled: \(rainView.settings.mouseEnabled)")
    }

    @objc func increaseMouseInfluence() {
        rainView.settings.mouseInfluenceIntensity += 0.0005
        print("Mouse influence intensity: \(rainView.settings.mouseInfluenceIntensity)")
    }

    @objc func decreaseMouseInfluence() {
        rainView.settings.mouseInfluenceIntensity = max(
            0.0, rainView.settings.mouseInfluenceIntensity - 0.0005)
        print("Mouse influence intensity: \(rainView.settings.mouseInfluenceIntensity)")
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
    var settings: RainSettings {
        didSet {
            self.preferredFramesPerSecond = settings.maxFPS
        }
    }

    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!

    private var raindrops: [Raindrop] = []
    private var splashes: [Splash] = []

    // Wind and ambient environment.
    private var wind: Float = 0.0
    private var ambientColor: SIMD4<Float> = SIMD4<Float>(0.05, 0.05, 0.1, 1.0)
    private var time: Float = 0.0

    // Compute current rain angle (in radians) from settings.angle.
    private var currentAngle: Float {
        return settings.angle * .pi / 180.0
    }

    // MARK: - Types

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
        var life: Float  // Current life remaining
        var startLife: Float  // For alpha calculation
        var intensity: Float  // Store the parent drop's intensity

        mutating func update() {
            life -= 0.016
            velocity *= 0.99
            velocity.y -= 0.003
            position += velocity
        }

        var alpha: Float {
            let norm = max(life / startLife, 0)
            return norm * norm * intensity  // Multiply by intensity
        }
    }

    // Uniforms for shader.
    struct RainUniforms {
        var rainColor: SIMD4<Float>
        var ambientColor: SIMD4<Float>
    }

    // Helper: Convert NSColor to SIMD4<Float>
    private func simd4(from color: NSColor) -> SIMD4<Float> {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return SIMD4<Float>(1, 1, 1, 1) }
        return SIMD4<Float>(
            Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent),
            Float(rgb.alphaComponent))
    }

    // New drop position helper – randomizes spawn location based on angle and aspect ratio.
    private func newDropPosition() -> SIMD2<Float> {
        let useAngleBias = abs(settings.angle) > 15
        let spawnFromSide: Bool
        if useAngleBias {
            spawnFromSide = Float.random(in: 0...1) > 0.3  // 70% chance side
        } else {
            let aspect = Float(self.bounds.width / self.bounds.height)
            let pTop = 1 / (1 + aspect)
            spawnFromSide = Float.random(in: 0...1) > pTop
        }
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

    // MARK: - Initializer

    init(frame frameRect: CGRect, device: MTLDevice, settings: RainSettings) {
        self.settings = settings
        super.init(frame: frameRect, device: device)

        self.preferredFramesPerSecond = settings.maxFPS  // Apply FPS setting
        self.commandQueue = device.makeCommandQueue()
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
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

    // MARK: - Setup Pipeline

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

        // Mouse influence is applied per-drop in the draw() loop.

        time += 0.016
        ambientColor = SIMD4<Float>(
            0.05 + 0.01 * sin(time * 0.05),
            0.05 + 0.01 * sin(time * 0.05 + 2.0),
            0.1 + 0.01 * sin(time * 0.05 + 4.0),
            1.0
        )
    }

    // MARK: - Create Raindrops

    // Modify the createRaindrops function
    func createRaindrops() {
        raindrops.removeAll()
        for _ in 0..<settings.numberOfDrops {
            let pos = newDropPosition()
            let special = Float.random(in: 0...1) < 0.01

            // Randomize length more dramatically
            let lengthRange = settings.length * 0.5...settings.length * 2.0
            let randomLength = Float.random(in: lengthRange)

            // Calculate color intensity based on length
            // Longer drops (closer) are brighter, shorter drops (far) are darker
            let normalizedLength =
                (randomLength - lengthRange.lowerBound)
                / (lengthRange.upperBound - lengthRange.lowerBound)
            let colorIntensity = 0.4 + (normalizedLength * 0.6)  // Range from 0.4 to 1.0

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

    // MARK: - Create Splash Particles

    private func createSplash(at position: SIMD2<Float>, intensity: Float) {
        let count = Int.random(in: 3...5)
        for _ in 0..<count {
            let randomAngle = Float.random(in: (Float.pi / 6)...(5 * Float.pi / 6))
            let speed = Float.random(in: 0.012...0.024)
            let vel = SIMD2<Float>(
                cos(randomAngle) * speed,
                sin(randomAngle) * speed * 3.0
            )
            let life = Float.random(in: 0.4...0.8)
            let splash = Splash(
                position: position, velocity: vel, life: life, startLife: life, intensity: intensity
            )
            splashes.append(splash)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        updateEnvironment()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = currentRenderPassDescriptor,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        var uniforms = RainUniforms(
            rainColor: simd4(from: settings.color), ambientColor: ambientColor)
        renderEncoder.setFragmentBytes(
            &uniforms, length: MemoryLayout<RainUniforms>.stride, index: 1)

        var raindropVertices: [Vertex] = []
        var splashVertices: [Vertex] = []

        // --- Update and Render Raindrops ---
        for i in 0..<raindrops.count {
            let effectiveSpeed =
                raindrops[i].isSpecial ? raindrops[i].speed * 0.5 : raindrops[i].speed
            var dx = sin(currentAngle) * effectiveSpeed + wind
            let dy = -cos(currentAngle) * effectiveSpeed

            // Mouse influence code remains the same
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
                // Only create splash if the raindrop is "close" (high intensity)
                let splashThreshold: Float = 0.85  // Only top 15% intensity drops create splashes
                if raindrops[i].colorIntensity > splashThreshold {
                    createSplash(at: raindrops[i].position, intensity: raindrops[i].colorIntensity)
                }

                let pos = newDropPosition()
                let special = Float.random(in: 0...1) < 0.01

                // When resetting raindrop, also randomize length and color intensity
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

            // Apply color intensity to the alpha value
            let dropAlpha = raindrops[i].colorIntensity
            raindropVertices.append(Vertex(position: raindrops[i].position, alpha: dropAlpha))
            raindropVertices.append(Vertex(position: dropEnd, alpha: dropAlpha))

            // Only create smear effect for high intensity drops
            if raindrops[i].isSpecial && raindrops[i].colorIntensity > 0.85 {
                let smearLength = raindrops[i].length * settings.smearFactor
                let smearEnd = raindrops[i].position + dropDir * smearLength
                let smearAlpha = raindrops[i].colorIntensity * 0.3
                raindropVertices.append(Vertex(position: raindrops[i].position, alpha: smearAlpha))
                raindropVertices.append(Vertex(position: smearEnd, alpha: smearAlpha))
            }
        }

        // Update and Render Splashes
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

        renderEncoder.endEncoding()
        if let drawable = currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
