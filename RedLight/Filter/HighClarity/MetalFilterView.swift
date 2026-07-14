import AppKit
import CoreVideo
import Metal
import QuartzCore

enum HighClarityMetalError: LocalizedError {
    case metalUnavailable
    case shaderLibraryUnavailable
    case shaderFunctionUnavailable
    case pipelineCreationFailed
    case textureCacheCreationFailed

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: "Metal is unavailable on this display."
        case .shaderLibraryUnavailable: "The High Clarity shader library could not be loaded."
        case .shaderFunctionUnavailable: "The High Clarity shader functions are missing."
        case .pipelineCreationFailed: "The High Clarity rendering pipeline could not be created."
        case .textureCacheCreationFailed: "The display texture cache could not be created."
        }
    }
}

enum RedLuminanceMath {
    static func srgbToLinear(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    static func linearToSRGB(_ value: Double) -> Double {
        let value = max(0, value)
        return value <= 0.0031308
            ? value * 12.92
            : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    static func transform(
        red: Double,
        green: Double,
        blue: Double,
        strength: Double,
        dimming: Double
    ) -> SIMD3<Double> {
        let luminance = 0.2126 * srgbToLinear(red)
            + 0.7152 * srgbToLinear(green)
            + 0.0722 * srgbToLinear(blue)
        let gain = 0.35 + 0.85 * min(max(strength, 0), 1)
        let outputRed = min(max(luminance * gain * (1 - dimming), 0), 1)
        return SIMD3(linearToSRGB(outputRed), 0, 0)
    }
}

@MainActor
final class MetalFilterView: NSView {
    let frameRenderer: MetalFrameRenderer
    private let metalLayer: CAMetalLayer

    init(frame: NSRect, device: MTLDevice) throws {
        metalLayer = CAMetalLayer()
        frameRenderer = try MetalFrameRenderer(
            layer: metalLayer,
            device: device
        )
        super.init(frame: frame)
        wantsLayer = true
        layer = metalLayer
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let scale = window?.screen?.backingScaleFactor
            ?? window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        metalLayer.frame = bounds
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }
}

final class MetalFrameRenderer: @unchecked Sendable {
    private struct FilterUniforms {
        var redGain: Float
        var dimming: Float
        var padding = SIMD2<Float>(repeating: 0)
    }

    private let layer: CAMetalLayer
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache
    private let uniformLock = NSLock()
    private var uniforms = FilterUniforms(redGain: 0.8, dimming: 0)

    init(layer: CAMetalLayer, device: MTLDevice) throws {
        self.layer = layer
        guard let commandQueue = device.makeCommandQueue() else {
            throw HighClarityMetalError.metalUnavailable
        }
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary() else {
            throw HighClarityMetalError.shaderLibraryUnavailable
        }
        guard let vertex = library.makeFunction(name: "redLuminanceVertex"),
              let fragment = library.makeFunction(name: "redLuminanceFragment")
        else {
            throw HighClarityMetalError.shaderFunctionUnavailable
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            pipelineState = try device.makeRenderPipelineState(
                descriptor: descriptor
            )
        } catch {
            throw HighClarityMetalError.pipelineCreationFailed
        }

        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        ) == kCVReturnSuccess, let cache else {
            throw HighClarityMetalError.textureCacheCreationFailed
        }
        textureCache = cache
    }

    func update(profile: FilterProfile) {
        uniformLock.lock()
        uniforms.redGain = Float(0.35 + 0.85 * profile.intensity)
        uniforms.dimming = Float(profile.dimming)
        uniformLock.unlock()
    }

    @discardableResult
    func render(pixelBuffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var wrappedTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &wrappedTexture
        ) == kCVReturnSuccess,
        let wrappedTexture,
        let texture = CVMetalTextureGetTexture(wrappedTexture),
        let drawable = layer.nextDrawable(),
        let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return false
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: pass
        ) else {
            return false
        }

        uniformLock.lock()
        var currentUniforms = uniforms
        uniformLock.unlock()

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(
            &currentUniforms,
            length: MemoryLayout<FilterUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }
}
