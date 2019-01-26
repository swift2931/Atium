//
//  Metal.swift
//  Live
//
//  Created by jimlai on 2018/9/11.
//  Copyright © 2018年 jimlai. All rights reserved.
//

import Foundation
import MetalKit
import VideoToolbox

infix operator ~~>: AdditionPrecedence

final class MTKDelagate: NSObject, MTKViewDelegate {
    var dev: MTLDevice? = MTLCreateSystemDefaultDevice()
    var texture: MTLTexture?
    var renderPipelineState: MTLRenderPipelineState?
    lazy var cq: MTLCommandQueue? = {
        return dev?.makeCommandQueue()
    }()
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }
    override init() {
        super.init()
        guard let lib = dev?.makeDefaultLibrary() else { return }
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.sampleCount = 1
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
        /**
         *  Vertex function to map the texture to the view controller's view
         */
        pipelineDescriptor.vertexFunction = lib.makeFunction(name: "mapTexture")
        /**
         *  Fragment function to display texture's pixels in the area bounded by vertices of `mapTexture` shader
         */ 
        pipelineDescriptor.fragmentFunction = lib.makeFunction(name: "displayTexture")

        do {
            try renderPipelineState = dev?.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            assert(false, "no pipelineState")
        }

    }

    func draw(in view: MTKView) {
        guard let commandBuffer = cq?.makeCommandBuffer() else {return}
        guard let currentRenderPassDescriptor = view.currentRenderPassDescriptor, let currentDrawable = view.currentDrawable, let renderPipelineState = renderPipelineState
            else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: currentRenderPassDescriptor) else {return}
        encoder.pushDebugGroup("RenderFrame")
        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        encoder.popDebugGroup()
        encoder.endEncoding()
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}

final class Atium {
    static var device = MTLCreateSystemDefaultDevice()
    static var textureCache: CVMetalTextureCache?
    var sbTexture: CVMetalTexture?
    var inTexture: MTLTexture?
    var next: ((MTLCommandBuffer) -> ())?
    lazy var outTexture: MTLTexture? = {
        let td = MTLTextureDescriptor()
        // Indicate we're creating a 2D texture.
        td.textureType = .type2D

        // Indicate that each pixel has a Blue, Green, Red, and Alpha channel,
        //    each in an 8 bit unnormalized value (0 maps 0.0 while 255 maps to 1.0)
        td.pixelFormat = .bgra8Unorm
        td.width = width
        td.height = height
        td.usage = MTLTextureUsage(rawValue: MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.shaderRead.rawValue)
        return Atium.device?.makeTexture(descriptor: td)
    }()
    static var cq: MTLCommandQueue? = {
        return Atium.device?.makeCommandQueue()
    }()
    static var lib: MTLLibrary? = {
        return Atium.device?.makeDefaultLibrary()
    }()
    var f: MTLFunction?
    var cps: MTLComputePipelineState?
    var cb: MTLCommandBuffer?
    var width = 0
    var height = 0

    init(_ fName: String) {
        guard let dev = Atium.device, let lib = Atium.lib, let cq = Atium.cq, let mf = lib.makeFunction(name: fName), let mcb = cq.makeCommandBuffer(), let mcps = try? dev.makeComputePipelineState(function: mf), CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &Atium.textureCache) == kCVReturnSuccess else {
            assert(false, "unexp init status")
            return
        }
        f = lib.makeFunction(name: fName)
        cps = mcps
        cb = mcb
    }

    func proc(_ sb: CMSampleBuffer) {
        guard let ib = CMSampleBufferGetImageBuffer(sb), let cache = Atium.textureCache else {
            return
        }

        width = CVPixelBufferGetWidth(ib)
        height = CVPixelBufferGetHeight(ib)
        var sbt: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, ib, nil, .bgra8Unorm, width, height, 0, &sbt) == kCVReturnSuccess else {
            return
        }
        guard let it = sbt, let texture = CVMetalTextureGetTexture(it) else {
            return
        }

        inTexture = texture
        run()
        cb?.waitUntilCompleted()

    }

    @discardableResult
    func chain(_ ain: Atium) -> Atium {
        inTexture = ain.inTexture
        width = ain.width
        height = ain.height
        ain.next = {_ in self.run()}
        return self
    }

    func enqueue() {
        guard let cps = cps, let cq = Atium.cq, let mcb = cq.makeCommandBuffer(), let ce = mcb.makeComputeCommandEncoder() else {
            return
        }

        let w = cps.threadExecutionWidth
        let h = cps.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)


        cb = mcb
        cb?.enqueue()
        if let next = next {
            cb?.addCompletedHandler(next)
        }

        // Encodes the compute pipeline state
        ce.setComputePipelineState(cps)

        // Encodes the input texture set it at location 0
        ce.setTexture(inTexture, index: 0)

        // Encodes the output texture set it at location 1
        ce.setTexture(outTexture, index: 1)

        // Encodes the dispatch of threadgroups (see later)
        ce.dispatchThreadgroups(MTLSize(width: width/16, height: height/16, depth: 1), threadsPerThreadgroup: threadsPerGroup)

        // Ends the encoding of the command
        ce.endEncoding()


    }

    func run() {
        enqueue()
        if let next = next {
            cb?.addCompletedHandler(next)
        }
        cb?.commit()
    }

    @discardableResult
    static func ~~>(_ ain: Atium, _ aout: Atium) -> Atium {
        return aout.chain(ain)
    }

    static func ~~>(_ aout: Atium, _ md: MTKDelagate) {
        aout.next = { [weak aout, weak md] _ in
            md?.texture =  aout?.outTexture
        }
    }
}


