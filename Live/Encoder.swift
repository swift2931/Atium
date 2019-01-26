//
//  Encoder.swift
//  Live
//
//  Created by jimlai on 2018/6/4.
//  Copyright © 2018年 jimlai. All rights reserved.
//

import Foundation
import AVFoundation
import VideoToolbox

final class Encoder {
    var width: Int32
    var height: Int32
    var nf: UInt32 = 0
    var numFrames: Int64 {
        get {
            let n = Int64(nf)
            nf = nf &+ 1
            return n
        }
        set {
            nf = UInt32(newValue)
        }
    }
    var out = UnsafeMutablePointer<VTCompressionSession?>.allocate(capacity: 1)
    func encode(_ buffer: CMSampleBuffer) {
        guard let op = out.pointee, let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            assert(false, "no session")
            return
        }
        let pt = CMTimeMake(value: numFrames, timescale: 1000)
        VTCompressionSessionEncodeFrame(op, imageBuffer: imageBuffer, presentationTimeStamp: pt, duration: CMTime.invalid, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
    }

    init(_ cb: @escaping VTCompressionOutputCallback, _ w: Int32, _ h: Int32) {
        width = w
        height = h
        let _ = VTCompressionSessionCreate(allocator: nil, width: w, height: h, codecType: kCMVideoCodecType_H264, encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: cb, refcon: nil, compressionSessionOut: out)
        /*
        guard let op = out.pointee else {
            assert(false, "no session")
            return
        }
        // real time
        VTSessionSetProperty(op, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)

        // frame rate
        var fps = 30
        let fpsRef = CFNumberCreate(kCFAllocatorDefault, .intType, &fps)
        VTSessionSetProperty(op, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef)


        // bitrate
        var bitRate = 800*1024
        let bitRateRef = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &bitRate)
        VTSessionSetProperty(op, kVTCompressionPropertyKey_AverageBitRate, bitRateRef)
        let limit = NSArray(array: [Double(bitRate) * 1.5/8, 1])
        VTSessionSetProperty(op, kVTCompressionPropertyKey_DataRateLimits, limit)

        // max key frame interval
        var frameInterval = 30
        let frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, .intType, &frameInterval)
        VTSessionSetProperty(op, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef)

        // prepare to encode
        VTCompressionSessionPrepareToEncodeFrames(op)
        */
    }

    deinit {
        out.deinitialize(count: 1)
        out.deallocate()
    }


}
