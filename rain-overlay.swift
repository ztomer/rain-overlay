import Cocoa
import Metal
import MetalKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var rainView: RainView!

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        window.isOpaque = false
        window.backgroundColor = NSColor.clear

        if let device = MTLCreateSystemDefaultDevice() {
            rainView = RainView(frame: window.contentView!.bounds, device: device)
            window.contentView = rainView
            rainView.layer?.isOpaque = false
            rainView.wantsLayer = true
            window.makeKeyAndOrderFront(nil)
        }
    }
}

class RainView: MTKView {
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var raindrops: [Raindrop] = []
    private var splashes: [Splash] = []
    private var time: Float = 0
    private let angle: Float = 30.0 * Float.pi / 180.0 // 30 degrees in radians

    struct Raindrop {
        var position: SIMD2<Float>
        var speed: Float
        var length: Float
    }

    struct Splash {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var life: Float
        var startLife: Float

        mutating func update() {
            life -= 0.016 // Assuming 60fps
            velocity.y -= 0.001 // Gravity
            position += velocity
        }

        var alpha: Float {
            return life / startLife
        }
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        guard let device = device else { fatalError("Metal is not supported") }
        super.init(frame: frameRect, device: device)

        self.commandQueue = device.makeCommandQueue()

        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = false
        self.layer?.isOpaque = false

        setupPipeline()
        createRaindrops()

        self.preferredFramesPerSecond = 60
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

        vertex float4 vertexShader(uint vertexID [[vertex_id]],
                                 constant float2 *vertices [[buffer(0)]]) {
            return float4(vertices[vertexID], 0.0, 1.0);
        }

        fragment float4 fragmentShader(float4 position [[position]],
                                     constant float &alpha [[buffer(1)]]) {
            return float4(0.7, 0.7, 1.0, alpha * 0.3);
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
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    private func createRaindrops() {
        for _ in 0..<200 {
            let raindrop = Raindrop(
                position: SIMD2<Float>(
                    Float.random(in: -1...1),
                    Float.random(in: -1...1)
                ),
                speed: Float.random(in: 0.005...0.015),
                length: Float.random(in: 0.05...0.15)
            )
            raindrops.append(raindrop)
        }
    }

    private func createSplash(at position: SIMD2<Float>) {
        let particleCount = Int.random(in: 3...5)
        for _ in 0..<particleCount {
            let angle = Float.random(in: -Float.pi...Float.pi)
            let speed = Float.random(in: 0.002...0.006)
            let velocity = SIMD2<Float>(
                cos(angle) * speed,
                sin(angle) * speed * 2 // More vertical spread
            )

            let splash = Splash(
                position: position,
                velocity: velocity,
                life: Float.random(in: 0.3...0.6),
                startLife: 0.5
            )
            splashes.append(splash)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        time += 1.0 / Float(preferredFramesPerSecond)

        renderEncoder.setRenderPipelineState(pipelineState)

        // Update and render raindrops
        for i in 0..<raindrops.count {
            let dx = sin(angle) * raindrops[i].speed
            let dy = -cos(angle) * raindrops[i].speed

            raindrops[i].position.x += dx
            raindrops[i].position.y += dy

            if raindrops[i].position.y < -1 {
                createSplash(at: raindrops[i].position)
                raindrops[i].position.y = 1
                raindrops[i].position.x = Float.random(in: -1...1)
            }

            let endX = raindrops[i].position.x + sin(angle) * raindrops[i].length
            let endY = raindrops[i].position.y - cos(angle) * raindrops[i].length

            let vertices: [Float] = [
                raindrops[i].position.x, raindrops[i].position.y,
                endX, endY
            ]

            var alpha: Float = 1.0
            renderEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
            renderEncoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: 2)
        }

        // Update and render splashes
        splashes = splashes.filter { $0.life > 0 }
        for i in 0..<splashes.count {
            splashes[i].update()

            let vertices: [Float] = [
                splashes[i].position.x, splashes[i].position.y,
                splashes[i].position.x + 0.01, splashes[i].position.y + 0.01
            ]

            var alpha = splashes[i].alpha
            renderEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
            renderEncoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: 2)
        }

        renderEncoder.endEncoding()

        if let drawable = currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()