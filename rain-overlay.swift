import Cocoa
import Metal
import MetalKit
import UniformTypeIdentifiers

// MARK: - RainSettings with Codable Conformance

struct RainSettings: Codable {
    var numberOfDrops: Int
    var speed: Float
    var angle: Float
    var color: NSColor
    var length: Float

    enum CodingKeys: String, CodingKey {
        case numberOfDrops, speed, angle, color, length
    }

    // Helper struct for NSColor components.
    struct ColorComponents: Codable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat
    }

    init(numberOfDrops: Int, speed: Float, angle: Float, color: NSColor, length: Float) {
        self.numberOfDrops = numberOfDrops
        self.speed = speed
        self.angle = angle
        self.color = color
        self.length = length
    }

    // Custom decoding: convert stored RGBA values into an NSColor.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        numberOfDrops = try container.decode(Int.self, forKey: .numberOfDrops)
        speed = try container.decode(Float.self, forKey: .speed)
        angle = try container.decode(Float.self, forKey: .angle)
        length = try container.decode(Float.self, forKey: .length)
        let components = try container.decode(ColorComponents.self, forKey: .color)
        color = NSColor(
            calibratedRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha)
    }

    // Custom encoding: extract NSColor's RGBA values.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(numberOfDrops, forKey: .numberOfDrops)
        try container.encode(speed, forKey: .speed)
        try container.encode(angle, forKey: .angle)
        try container.encode(length, forKey: .length)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if let colorRGB = color.usingColorSpace(.deviceRGB) {
            colorRGB.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        let components = ColorComponents(red: red, green: green, blue: blue, alpha: alpha)
        try container.encode(components, forKey: .color)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var rainView: RainView!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        setupStatusBarItem()

        let screen = NSScreen.main!
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.hasShadow = false
        window.alphaValue = 1.0
        window.backgroundColor = NSColor.clear

        if let device = MTLCreateSystemDefaultDevice() {
            let settings = RainSettings(
                numberOfDrops: 200,
                speed: 0.01,
                angle: 30.0,
                color: NSColor.white,
                length: 0.1
            )
            rainView = RainView(
                frame: window.contentView!.bounds,
                device: device,
                settings: settings
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
                in: button
            )
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
        rainView.settings.angle = max(5.0, rainView.settings.angle - 5)
        rainView.createRaindrops()
    }

    @objc func increaseLength() {
        rainView.settings.length += 0.05
    }

    @objc func decreaseLength() {
        rainView.settings.length = max(0.05, rainView.settings.length - 0.05)
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

    // MARK: - Save/Load Configuration

    @objc func saveConfig() {
        let savePanel = NSSavePanel()
        // Use allowedContentTypes (UTType.json) instead of deprecated allowedFileTypes.
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
        // Use allowedContentTypes (UTType.json) instead of deprecated allowedFileTypes.
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
            let settings = try decoder.decode(RainSettings.self, from: data)
            rainView.settings = settings
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

    struct Raindrop {
        var position: SIMD2<Float>
        var speed: Float
        var length: Float
    }

    struct Splash {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var life: Float

        mutating func update() {
            life -= 0.016
            velocity.y -= 0.001
            position += velocity
        }

        var alpha: Float {
            return max(life / 0.5, 0)
        }
    }

    init(frame: CGRect, device: MTLDevice, settings: RainSettings) {
        self.settings = settings
        super.init(frame: frame, device: device)
        self.commandQueue = device.makeCommandQueue()
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = false

        setupPipeline()
        createRaindrops()

        self.preferredFramesPerSecond = 60
        self.isPaused = false
        self.enableSetNeedsDisplay = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPipeline() {
        guard let device = self.device else { return }

        let shaderSource = """
            #include <metal_stdlib>
            using namespace metal;

            vertex float4 vertexShader(uint vertexID [[vertex_id]], constant float2 *vertices [[buffer(0)]]) {
                return float4(vertices[vertexID], 0.0, 1.0);
            }

            fragment float4 fragmentShader(float4 position [[position]], constant float &alpha [[buffer(1)]]) {
                return float4(0.7, 0.7, 1.0, alpha);
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

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    func createRaindrops() {
        raindrops.removeAll()

        for _ in 0..<settings.numberOfDrops {
            let x = Float.random(in: -1.5...1.5)
            let y = Float.random(in: 1.0...2.0)
            let position = SIMD2<Float>(x, y)
            let speed = Float.random(in: settings.speed...settings.speed * 2)
            let length = Float.random(in: settings.length...settings.length * 2)
            raindrops.append(Raindrop(position: position, speed: speed, length: length))
        }
    }

    private func createSplash(at position: SIMD2<Float>) {
        for _ in 0..<5 {
            let angle = Float.random(in: -Float.pi...Float.pi)
            let speed = Float.random(in: 0.002...0.006)
            let velocity = SIMD2<Float>(cos(angle) * speed, sin(angle) * speed * 2)
            splashes.append(Splash(position: position, velocity: velocity, life: 0.5))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = currentRenderPassDescriptor,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        let angleInRadians = settings.angle * (.pi / 180)

        // Draw raindrops.
        for i in 0..<raindrops.count {
            raindrops[i].position.x += sin(angleInRadians) * raindrops[i].speed
            raindrops[i].position.y -= cos(angleInRadians) * raindrops[i].speed

            if raindrops[i].position.y < -1.5 || raindrops[i].position.x > 1.5
                || raindrops[i].position.x < -1.5
            {
                createSplash(at: raindrops[i].position)
                raindrops[i].position = SIMD2<Float>(Float.random(in: -1.5...1.5), 1.5)
            }

            let endX = raindrops[i].position.x + sin(angleInRadians) * raindrops[i].length
            let endY = raindrops[i].position.y - cos(angleInRadians) * raindrops[i].length

            let vertices: [SIMD2<Float>] = [
                raindrops[i].position,
                SIMD2<Float>(endX, endY),
            ]

            var alpha: Float = 1.0
            renderEncoder.setVertexBytes(
                vertices,
                length: MemoryLayout<SIMD2<Float>>.stride * vertices.count,
                index: 0
            )
            renderEncoder.setFragmentBytes(
                &alpha,
                length: MemoryLayout<Float>.stride,
                index: 1
            )
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 2)
        }

        // Draw splashes.
        splashes = splashes.filter { $0.life > 0 }
        for i in 0..<splashes.count {
            splashes[i].update()

            let vertices: [SIMD2<Float>] = [
                splashes[i].position,
                splashes[i].position + SIMD2<Float>(0.01, 0.01),
            ]

            var alpha = splashes[i].alpha
            renderEncoder.setVertexBytes(
                vertices,
                length: MemoryLayout<SIMD2<Float>>.stride * vertices.count,
                index: 0
            )
            renderEncoder.setFragmentBytes(
                &alpha,
                length: MemoryLayout<Float>.stride,
                index: 1
            )
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 2)
        }

        renderEncoder.endEncoding()

        if let drawable = currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
        self.setNeedsDisplay(self.bounds)
    }
}
