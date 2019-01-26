//
//  RtmpSession.swift
//  Live
//
//  Created by jimlai on 2018/6/6.
//  Copyright © 2018年 jimlai. All rights reserved.
//

import Foundation
import VideoToolbox

protocol SessionControl: class {
    var rd: RtmpStreamManager {get set}
    func onCmdResponse(_ cr: CmdReader)
    func prepare()
}

extension SessionControl {
}


enum AMFVersion {
    case amf0, amf3
}

final class CmdTracker {
    static var tid: UInt8 = 0
    static var cts = [UInt8: CmdTracker]()
    static func getTid() -> UInt8 {
        CmdTracker.tid += 1
        return CmdTracker.tid
    }
    static func makeCmd(_ cmd: RtmpMsg) -> CmdTracker {
        let ct = CmdTracker(cmd, CmdTracker.getTid())
        CmdTracker.cts[ct.tid] = ct
        return ct
    }
    var cmd: RtmpMsg
    var tid: UInt8
    init(_ cmd: RtmpMsg, _ tid: UInt8) {
        self.cmd = cmd
        self.tid = tid
    }
}


class RtmpSessionManager: SessionControl {
    static let amfv: AMFVersion = .amf0
    lazy var rd: RtmpStreamManager = {
        let rsm = RtmpStreamManager(url, port)
        rsm.session = self
        return rsm
    }()
    var msid: UInt32 = 5
    let url: String
    let port: UInt32
    var cqs = [CmdTracker]()
    var isStreaming = false
    init(_ url: String, _ port: UInt32) {
        self.url = url
        self.port = port
        //let data = "iam: john".data(using: .ascii)!
        //_ = data.withUnsafeBytes { ops.write($0, maxLength: data.count) }
    }

    func prepare() {
        CmdTracker.cts[1] = CmdTracker(.connect, 1)
    }

    func createStream() {
        let cs = CmdTracker.makeCmd(.createStream)
        rd.createStream(cs.tid)
    }

    func publish() {
        let cs = CmdTracker.makeCmd(.publish)
        rd.publish(cs.tid)
    }

    func onCmdResponse(_ cr: CmdReader) {
        guard cr.onStatus == false else {
            rd.setChunkSize()
            isStreaming = true
            return
        }
        guard let ct = CmdTracker.cts[cr.tid] else {
            return
        }
        switch ct.cmd {
        case .connect:
            cr.parseConnect()
            createStream()
            dp(cr.cmdObj, cr.resObj)

        case .createStream:
            cr.parseCreateStream()
            dp(cr.streamId)
            publish()

        default:
            break
        }
    }

    func onEncoded(_ sampleBuffer: CMSampleBuffer?) {
        guard let sb = sampleBuffer, isStreaming else {
            //dp("discarded")
            return
        }
        rd.stream(sb)
    }

}

func outputCallback(_ refCon: UnsafeMutableRawPointer?, _ sourceFrameRefCon: UnsafeMutableRawPointer?, _ status: OSStatus, _ infoFlags: VTEncodeInfoFlags, _ sampleBuffer: CMSampleBuffer?) {
    //dp("osstatus \(status)", infoFlags)
    guard status == 0 else {
        return
    }
    rs.onEncoded(sampleBuffer)
}
