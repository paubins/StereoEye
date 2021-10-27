//
//  MetalView.swift
//  MetalCamera
//
//  Created by Greg on 24/07/2019.
//  Copyright © 2019 GS. All rights reserved.
//

import CoreVideo
import MetalKit
import MetalPerformanceShaders
import simd

final class MetalView: MTKView {
    var standardPipeline: MTLRenderPipelineState!
    var alphaPipeline: MTLRenderPipelineState!

    lazy var buttonTexture: MTLTexture? = {
        if let image = UIImage(named: "buttons.png") {
            return try! MTKTextureLoader(device: self.device!)
                .newTexture(cgImage: image.cgImage!, options: nil)
        }
        return nil
    }()

    var secondaryCallerPixelBuffer: CVPixelBuffer? {
        didSet {
            setNeedsDisplay()
        }
    }

    var mainCallerPixelBuffer: CVPixelBuffer? {
        didSet {
            setNeedsDisplay()
        }
    }

    private var textureCache: CVMetalTextureCache?
    private var commandQueue: MTLCommandQueue?

    private var secondaryCaller: MTLBuffer! = nil
    private var mainCallerBuffer: MTLBuffer! = nil
    private var buttonsBuffer: MTLBuffer! = nil

    private var numVertices: Int = 0
    private var viewportSize: vector_uint2?

    var bufferCallback: ((MTLTexture) -> Void)?

    required init(coder: NSCoder) {

        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Unable to initialize GPU device")
        }

        commandQueue = metalDevice.makeCommandQueue()

        var textCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textCache)
            != kCVReturnSuccess
        {
            fatalError("Unable to allocate texture cache.")
        } else {
            textureCache = textCache
        }

        super.init(coder: coder)
        self.device = metalDevice
        self.framebufferOnly = false
        self.preferredFramesPerSecond = 60
        //        self.backgroundColor = .black
        //        self.isOpaque = true
        //        self.framebufferOnly = false
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.drawableSize = self.bounds.size
        //        self.enableSetNeedsDisplay = true
        //        self.depthStencilPixelFormat = .depth32Float
        self.colorPixelFormat = .bgra8Unorm
        self.prepareFunctions()

    }

    override func draw(_ rect: CGRect) {
        autoreleasepool {
            if !rect.isEmpty {
                self.render()
            }
        }
    }

    fileprivate func createPipeline(_ metalDevice: MTLDevice, alpha: Bool = false) throws
        -> MTLRenderPipelineState
    {
        // step 4-5: create a vertex shader & fragment shader
        // A vertex shader is simply a tiny program that runs on the GPU, written in a C++-like language called the Metal Shading Language.

        let library = metalDevice.makeDefaultLibrary()
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library!.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library!.makeFunction(name: "samplingShader")
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat

        if alpha {
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .destinationAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .destinationAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusBlendAlpha
        }

        return try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    fileprivate func createPipelineWithAlpha(_ metalDevice: MTLDevice) throws
        -> MTLRenderPipelineState
    {
        return try self.createPipeline(metalDevice, alpha: true)
    }

    func prepareFunctions() {
        guard let metalDevice = self.device else { fatalError("Expected a Metal device.") }
        do {

            let width = Float(self.bounds.size.width) / 2
            let height = Float(self.bounds.size.height) / 2
            
            let secondaryCallerVertexData:[AAPLVertex] = createQuad(
                tl: (50, -50), tr: (-50, -50),
                bl: (-50, 50), bl2: (50, -50),
                br: (-50, 50), tr2: (50, 50))
            let dataSize =
                secondaryCallerVertexData.count
                * MemoryLayout.size(ofValue: secondaryCallerVertexData[0])
            // assign to the buffer

            // fixed error here with nil not being an acceptable parameter for 'options'
            // http://stackoverflow.com/questions/29584463/ios-8-3-metal-found-nil-while-unwrapping-an-optional-value
            secondaryCaller = metalDevice.makeBuffer(
                bytes: secondaryCallerVertexData,
                length: dataSize,
                options: .storageModeShared)

            mainCallerBuffer = metalDevice.makeBuffer(
                bytes: createQuad(
                    tl: (width, -height), tr: (-width, -height),
                    bl: (-width, height), bl2: (width, -height),
                    br: (-width, height), tr2: (width, height)),
                length: dataSize,
                options: .storageModeShared)

            buttonsBuffer = metalDevice.makeBuffer(
                bytes: createQuad(
                    //Triangle1: top left, top right, bottom left
                    tl: (width, -height), tr: (-width + 50, -height + 50), bl: (-width + 50, -height),
                    //Triangle2: bottom left, bottom right, top right
                    bl2: (width - 50, -height + 50), br: (-width - 50, -height), tr2: (width - 50, -height)),
                length: dataSize,
                options: .storageModeShared)

            numVertices = dataSize / MemoryLayout<AAPLVertex>.size

            standardPipeline = try createPipeline(metalDevice)
            alphaPipeline = try createPipelineWithAlpha(metalDevice)

            viewportSize = vector_uint2(
                x: UInt32(self.bounds.size.width), y: UInt32(self.bounds.size.height))
        } catch {
            print("Unexpected error: \(error).")
        }
    }

    fileprivate func createQuad(
        tl: (Float, Float), tr: (Float, Float), bl: (Float, Float),
        bl2: (Float, Float), br: (Float, Float), tr2: (Float, Float)
    )
        -> [AAPLVertex]
    {
        func get_simd(c: (Float, Float)) -> simd_float2 {
            return simd_make_float2(c.0, c.1)
        }

        return [
            // triangle one
            AAPLVertex(
                position: get_simd(c: tl),
                textureCoordinate: simd_make_float2(1.0, 1.0)),
            AAPLVertex(
                position: get_simd(c: tr),
                textureCoordinate: simd_make_float2(0.0, 1.0)),
            AAPLVertex(
                position: get_simd(c: bl),
                textureCoordinate: simd_make_float2(0.0, 0.0)),

            // triangle two
            AAPLVertex(
                position: get_simd(c: bl2),
                textureCoordinate: simd_make_float2(1.0, 1.0)),
            AAPLVertex(
                position: get_simd(c: br),
                textureCoordinate: simd_make_float2(0.0, 0.0)),
            AAPLVertex(
                position: get_simd(c: tr2),
                textureCoordinate: simd_make_float2(1.0, 0.0)),
        ]

    }

    private func render() {
        guard let drawable: CAMetalDrawable = self.currentDrawable else {
            fatalError("Failed to create drawable")
        }
        guard let commandBuffer = commandQueue!.makeCommandBuffer() else { return }

        self.encodeTexture(
            buffer: self.mainCallerBuffer,
            pixelBuffer: self.mainCallerPixelBuffer,
            pipeline: self.standardPipeline,
            commandBuffer: commandBuffer)

        self.encodeTexture(
            buffer: self.secondaryCaller,
            pixelBuffer: self.secondaryCallerPixelBuffer,
            pipeline: self.standardPipeline,
            commandBuffer: commandBuffer)

        if let texture = buttonTexture {
            self.encodeTexture(
                buffer: self.buttonsBuffer,
                texture: texture,
                pipeline: self.alphaPipeline,
                commandBuffer: commandBuffer)
        }

        let texture = drawable.texture
        commandBuffer.addCompletedHandler { commandBuffer in
            if let callback = self.bufferCallback {
                callback(texture)
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func encodeTexture(
        buffer: MTLBuffer, pixelBuffer: CVImageBuffer? = nil, pipeline: MTLRenderPipelineState,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let pixelBuffer = pixelBuffer else {
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache!, pixelBuffer, nil, .bgra8Unorm, width, height, 0,
            &cvTextureOut)
        guard let cvTexture = cvTextureOut, let inputTexture = CVMetalTextureGetTexture(cvTexture)
        else {
            fatalError("Failed to create metal textures")
        }
        
        self.encodeTexture(buffer: buffer, texture: inputTexture, pipeline: pipeline, commandBuffer: commandBuffer)
    }

    private func encodeTexture(
        buffer: MTLBuffer, texture:MTLTexture, pipeline: MTLRenderPipelineState,
        commandBuffer: MTLCommandBuffer
    ) {
        
        guard let passDescriptor = self.currentRenderPassDescriptor else { return }
        passDescriptor.colorAttachments[0].loadAction = .load
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            return
        }
        encoder.setViewport(
            MTLViewport(
                originX: 0, originY: 0,
                width: self.bounds.size.width,
                height: self.bounds.size.height,
                znear: -1.0, zfar: 1.0))

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setVertexBytes(&viewportSize, length: MemoryLayout<vector_uint2>.size, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: numVertices)
        encoder.endEncoding()
    }
}
