//
//  YUY2Renderer.swift
//  UVCDisplay
//

import Metal
import MetalKit

private struct YUY2Params {
    var width: UInt32
    var height: UInt32
}

final class YUY2Renderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let yuy2Pipeline: MTLRenderPipelineState
    private let scalingPipeline: MTLRenderPipelineState

    private static let bufferCount = 3
    private var frameBuffers = [MTLBuffer?](repeating: nil, count: bufferCount)
    private var bufferInUse = [Bool](repeating: false, count: bufferCount)
    private var bufferBytes = 0

    private var rgbTexture: MTLTexture?
    private var texW = 0, texH = 0

    private let lock = NSLock()
    private var readyIndex = -1
    private var frameW = 0, frameH = 0

    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "yuy2_vertex"),
              let yuy2Fragment = library.makeFunction(name: "yuy2_fragment"),
              let scalingFragment = library.makeFunction(name: "rgb_scaling_fragment")
        else { return nil }

        self.device = device
        self.queue = queue

        let yuy2Descriptor = MTLRenderPipelineDescriptor()
        yuy2Descriptor.label = "YUY2 to RGB"
        yuy2Descriptor.vertexFunction = vfn
        yuy2Descriptor.fragmentFunction = yuy2Fragment
        yuy2Descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let scalingDescriptor = MTLRenderPipelineDescriptor()
        scalingDescriptor.label = "Linear RGB scaling"
        scalingDescriptor.vertexFunction = vfn
        scalingDescriptor.fragmentFunction = scalingFragment
        scalingDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let yuy2Pipeline = try? device.makeRenderPipelineState(descriptor: yuy2Descriptor),
              let scalingPipeline = try? device.makeRenderPipelineState(descriptor: scalingDescriptor)
        else {
            return nil
        }
        self.yuy2Pipeline = yuy2Pipeline
        self.scalingPipeline = scalingPipeline
        super.init()

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 1)
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.delegate = self
    }

    /// Copies frame data before the libuvc callback returns.
    @discardableResult
    func update(bytes: UnsafeRawPointer, width: Int, height: Int, length: Int) -> Bool {
        guard width > 0,
              height > 0,
              width.isMultiple(of: 2),
              length >= width * height * 2
        else { return false }

        let packedLength = width * height * 2

        lock.lock()
        defer { lock.unlock() }

        let sizeChanged = frameW != width || frameH != height

        if bufferBytes != packedLength {
            for i in 0..<Self.bufferCount {
                frameBuffers[i] = device.makeBuffer(length: packedLength,
                                                    options: .storageModeShared)
                bufferInUse[i] = false
            }
            bufferBytes = packedLength
            readyIndex = -1
        }

        var writeIndex = -1
        for i in 0..<Self.bufferCount where !bufferInUse[i] && i != readyIndex {
            writeIndex = i
            break
        }
        if writeIndex < 0 {
            for i in 0..<Self.bufferCount where !bufferInUse[i] {
                writeIndex = i
                break
            }
        }
        guard writeIndex >= 0, let buffer = frameBuffers[writeIndex] else {
            return sizeChanged
        }

        memcpy(buffer.contents(), bytes, packedLength)
        readyIndex = writeIndex
        frameW = width
        frameH = height
        return sizeChanged
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        var conversionIndex = -1
        var yuy2Buffer: MTLBuffer?
        var w = 0, h = 0

        lock.lock()
        if readyIndex >= 0, let buffer = frameBuffers[readyIndex] {
            conversionIndex = readyIndex
            yuy2Buffer = buffer
            w = frameW
            h = frameH
            bufferInUse[conversionIndex] = true
            readyIndex = -1
            ensureTextures(width: w, height: h)
        }
        lock.unlock()

        guard let rgbTexture,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer()
        else {
            releaseBuffer(conversionIndex)
            return
        }

        if let yuy2Buffer, conversionIndex >= 0 {
            var params = YUY2Params(width: UInt32(w), height: UInt32(h))
            let conversionPass = MTLRenderPassDescriptor()
            conversionPass.colorAttachments[0].texture = rgbTexture
            conversionPass.colorAttachments[0].loadAction = .dontCare
            conversionPass.colorAttachments[0].storeAction = .store

            guard let conversionEncoder = cmd.makeRenderCommandEncoder(
                descriptor: conversionPass
            ) else {
                releaseBuffer(conversionIndex)
                return
            }
            conversionEncoder.label = "Convert YUY2 to RGB"
            conversionEncoder.setRenderPipelineState(yuy2Pipeline)
            conversionEncoder.setFragmentBuffer(yuy2Buffer, offset: 0, index: 0)
            conversionEncoder.setFragmentBytes(&params,
                                               length: MemoryLayout<YUY2Params>.stride,
                                               index: 1)
            conversionEncoder.drawPrimitives(type: .triangle,
                                             vertexStart: 0,
                                             vertexCount: 3)
            conversionEncoder.endEncoding()

            let releaseIndex = conversionIndex
            cmd.addCompletedHandler { [weak self] _ in
                self?.releaseBuffer(releaseIndex)
            }
            conversionIndex = -1
        }

        guard let scalingEncoder = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
            cmd.commit()
            releaseBuffer(conversionIndex)
            return
        }
        scalingEncoder.label = "Scale RGB to drawable"
        scalingEncoder.setRenderPipelineState(scalingPipeline)
        scalingEncoder.setFragmentTexture(rgbTexture, index: 0)
        scalingEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        scalingEncoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private func releaseBuffer(_ index: Int) {
        guard index >= 0 else { return }
        lock.lock()
        if index < bufferInUse.count { bufferInUse[index] = false }
        lock.unlock()
    }

    private func ensureTextures(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        if texW == width, texH == height, rgbTexture != nil { return }

        let rgbDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        rgbDescriptor.usage = [.renderTarget, .shaderRead]
        rgbDescriptor.storageMode = .private
        rgbTexture = device.makeTexture(descriptor: rgbDescriptor)

        texW = width
        texH = height
    }
}
