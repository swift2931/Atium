//
//  RtmpStream.swift
//  Live
//
//  Created by jimlai on 2018/6/6.
//  Copyright © 2018年 jimlai. All rights reserved.
//

import Foundation
import VideoToolbox

struct RC {
    static let windowSizeC = Int(UInt16.max)
}


func dp(_ any: Any...) {
    print(any)
}

enum ReadyState: UInt8 {
    case uninitialized = 0
    case versionSent   = 1
    case ackSent       = 2
    case handshakeDone = 3
    case closing       = 4
    case closed        = 5
}

enum MsgStreams: UInt32 {
    case ping = 0x02,//Ping 和ByteRead通道
         cmd = 0x03,//invoke通道,connect,publish,connect
         audio  = 0x04,//audio or video,这里只作为音频数据
         video  = 0x06, //video //官方文档保留,实际可以发送视音频数据
         userControl = 0
}


class RtmpStreamManager: NSObject, StreamDelegate {
    let ips: InputStream
    let ops: OutputStream
    var buf = Data()
    var totalBytesIn: Int64 = 0
    var state: ReadyState = .uninitialized
    var handshake = RTMPHandshake()
    var _numInvokes: Double = 0
    var numInvokes: Double {
        _numInvokes += 1
        return _numInvokes
    }
    let url: String
    weak var session: SessionControl?
    var pChunkSize: Int = 4096
    var pMsgType: MsgTypes = .video
    var pTimeDelta: UInt32 = 30
    var pcsid: UInt8 = 0x09
    var pmsid: MsgStreams = .video


    init(_ url: String, _ port: UInt32) {
        self.url = url
        var inputStream: Unmanaged<CFReadStream>?
        var outputStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, url as CFString, port, &inputStream, &outputStream)
        guard let input = inputStream?.takeRetainedValue(), let output = outputStream?.takeRetainedValue()  else {
            assert(false, "no stream")
            ips = InputStream()
            ops = OutputStream()
            super.init()
            return
        }
        ips = input
        ops = output

        ips.schedule(in: .current, forMode: RunLoop.Mode.common)
        ops.schedule(in: .current, forMode: RunLoop.Mode.common)

        ips.open()
        ops.open()
        super.init()
        self.ips.delegate = self
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            read()
        case .errorOccurred, .endEncountered:
            ips.close()
        default:
            break
        }
    }
    func read() {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: RC.windowSizeC)
        let len = ips.read(buffer, maxLength: RC.windowSizeC)
        if len > 0 {
            totalBytesIn += Int64(len)
            buf.append(buffer, count: len)
            updateState()
        }
    }
    func write(_ data: Data) {
        _ = data.withUnsafeBytes { ops.write($0, maxLength: data.count) }
    }

    func write(_ chunk: Chunk) {
        let data = chunk.data
        _ = data.withUnsafeBytes { ops.write($0, maxLength: data.count) }
    }

    func updateState() {
        switch state {
        case .versionSent:
            guard buf.count >= 2*RTMPHandshake.sigSize + 1 else {
                break
            }
            write(handshake.c2packet(buf))
            buf.removeSubrange(0...2*RTMPHandshake.sigSize)
            state = .handshakeDone
            session?.prepare()
            connect(url, 1)
        case .handshakeDone:
            guard buf.count > 0 else {
                break
            }
            buf = ChunkReader.parse(buf, handler(_:))
        default:
            break
        }
    }

    func startHandshake() {
        write(handshake.c0c1packet)
        state = .versionSent
    }

    func handler(_ msg: Chunk) {
        switch msg {
        case let f as Fmt0:
            handle(f)
        default:
            break
        }
    }

    func handle(_ fmt0: Fmt0) {
        switch fmt0.type {
        case 1:
            CR.chunkSize = fmt0.p4
        case 3:
            print("ack received")
                // user control msg
        case 4:
            handleUserControl(fmt0)
        case 5:
            CR.sWinAckSize = fmt0.payload.uint()
        case 6:
            CR.winAckSize = fmt0.p4

        case MsgTypes.cmd.rawValue:
            let cr = CmdReader.read(fmt0.payload)
            session?.onCmdResponse(cr)

        default:
            print(fmt0.type)
        }
    }
    func handleUserControl(_ fmt0: Fmt0) {
        guard let st = fmt0.eventType else {
            return
        }
        switch st {
        case 0:
            if let _ = fmt0.getEventData() as UInt32?, let csid = fmt0.getEventData() as UInt32? {
                dp("stream \(csid) begin")

            }
        case 6:
            if let ts = fmt0.getEventData() as UInt32?, let pong = RtmpMsg.pong(ts).toMsg(ChunkReader.curMID) {
                write(pong.data)
            }
        default:
            break
        }

    }

    func connect(_ url: String, _ tid: UInt8) {
        write(CW.makeMsg(.cmd, MsgStreams.cmd, CW.pConnect(url, tid)))
    }

    func createStream(_ tid: UInt8) {
        write(CW.makeMsg(.cmd, MsgStreams.cmd, CW.pCreateStream(tid)))
    }

    func publish(_ tid: UInt8) {
        write(CW.makeMsg(.cmd, .cmd, CW.pPublish(tid, "sg1")))
    }

    func setChunkSize() {
        write(CW.makeMsg(.chunkSize, .userControl, CW.pChunkSize(), 2))
    }

    func send(_ nalu: Data, _ isKey: Bool) {
        guard pChunkSize > 0 else {
            dp("zero chunk size")
            return
        }
        var msg = getFmt1(CW.pVideo(nalu, isKey))
        //dp(msg.data.hexEncodedString())
        guard nalu.count > pChunkSize else {
            //let msg = CW.makeMsg(.video, .video, CW.pVideo(nalu))
            write(msg)
            return
        }
        let payload = msg.payload
        let firstPayload = payload.subdata(in: 0 ..< pChunkSize)
        msg.payload = firstPayload
        write(msg)
        var p = pChunkSize
        while p < payload.count {
            let end = min(payload.count, p+pChunkSize)
            let subs = payload.subdata(in: p ..< end)
            let splitMsg = getFmt3(subs)
            write(splitMsg)
            p = end
        }
    }
    func stream(_ sb: CMSampleBuffer) {
        let avc = AVC(sb)
        if let header = avc.avcheader {
            let headerMsg = avc.getHeaderMsg(pcsid, header, pTimeDelta)
            dp(headerMsg.data.hexEncodedString())
            write(headerMsg)
            AVC.needToSendAVCHeader = false
        }
        guard AVC.needToSendAVCHeader == false, let nalu = avc.nalu else {
            dp("nalu not sent")
            return
        }
        DispatchQueue.main.async {
            self.send(nalu, avc.isKey)
        }
    }

    func getFmt1(_ payload: Data) -> Fmt1 {
        return CW.makeMsg(pmsid, pcsid, payload, pTimeDelta, pMsgType)
    }

    func getFmt3(_ payload: Data) -> Fmt3 {
        return CW.makeMsg(pmsid, pcsid, payload, pTimeDelta, pMsgType)
    }

}

struct AVC {
    static var needToSendAVCHeader = true
    var sps: Data?
    var pps: Data?

    static var naluLenBytes: UInt8 = 4
    init(_ sb: CMSampleBuffer) {
        // check if keyframe
        let arr: NSArray = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true)!
        let dict = arr.object(at: 0) as! NSDictionary
        let key: NSString = kCMSampleAttachmentKey_NotSync
        let isKeyframe = dict[key] == nil ? true : false
        if isKeyframe == true, let format = CMSampleBufferGetFormatDescription(sb) {
            isKey = true
            // get sps
            let sparameterSetSize = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            //let sparameterSetCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            let pnaluLenBytes = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
            let sparameterSet = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: 1)

            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: sparameterSet, parameterSetSizeOut: sparameterSetSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: pnaluLenBytes)
            AVC.naluLenBytes = UInt8(pnaluLenBytes.pointee)

            // get pps
            let pparameterSetSize = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            //let pparameterSetCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            let pparameterSet = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: 1)
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 1, parameterSetPointerOut: pparameterSet, parameterSetSizeOut: pparameterSetSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)

            if let spsData = sparameterSet.pointee, let ppsData = pparameterSet.pointee {
                sps = Data(bytes: spsData, count: sparameterSetSize.pointee)
                pps = Data(bytes: ppsData, count: pparameterSetSize.pointee)
            }
            deallocate([sparameterSetSize, pparameterSetSize])
            deallocate([sparameterSet, pparameterSet])
            deallocate([pnaluLenBytes])
        }
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sb) else {
            assert(false, "no AVC data")
            return
        }
        let totalLength = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        let dataPointer = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity: 1)
        let _ = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: totalLength, dataPointerOut: dataPointer)
        if let dp = dataPointer.pointee {
            nalu = Data(bytes: dp, count: totalLength.pointee)
        }
        //dp(nalu?.hexEncodedString() ?? "", totalLength.pointee)
        deallocate([totalLength])
        deallocate([dataPointer])

    }
    func deallocate<T>(_ ps: [UnsafeMutablePointer<T>]) {
        for p in ps {
            p.deinitialize(count: 1)
            p.deallocate()
        }
    }
    var nalu: Data?
    var isKey = false
    var avcheader: Data? {
        guard let sps = sps, let pps = pps else {
            return nil
        }
        let ba = ByteArray()
        dp(sps.hexEncodedString())
        guard AVC.naluLenBytes > 0, sps.count > 3 else {
            return nil
        }
        ba.write(0x01 as UInt8).write(sps[1]).write(sps[2]).write(sps[3]).write((0xfc + (AVC.naluLenBytes-1)) as UInt8).write(0xe1 as UInt8).write(UInt16(sps.count)).writeBytes(sps).write(1 as UInt8)
                .write(UInt16(pps.count)).writeBytes(pps)
        return ba.data
    }

    static func avcToAnnexB(_ avc: Data) -> Data {
        let annex = ByteArray()
        var p = 0
        let start = Data(bytes: [0, 0, 0, 1])
        while p < avc.count {
            let pEnd = p+Int(AVC.naluLenBytes)
            let len: UInt32 = avc.subdata(in: p ..< pEnd).uint()
            let np = pEnd+Int(len)
            annex.writeBytes(start).writeBytes(avc.subdata(in: pEnd ..< np))
            p = np
        }
        return annex.data
    }
    func getHeaderMsg(_ csid: UInt8, _ header: Data, _ delta: UInt32) -> Chunk {
        if AVC.needToSendAVCHeader {
            return CW.makeMsg(.video, .video, CW.pVideoHeader(header), csid, nil, 0)
        }
        else {
            return CW.makeMsg(.video, csid, CW.pVideoHeader(header), delta, .video) as Fmt1
        }
    }

}

struct RTMPHandshake {
    static let sigSize: Int = 1536
    static let protocolVersion: UInt8 = 3

    var timestamp: TimeInterval = 0

    var c0c1packet: Data {
        let packet = ByteArray()
            .write(RTMPHandshake.protocolVersion)
            .write(Int32(Date().timeIntervalSince1970))
            .writeBytes(Data([0x00, 0x00, 0x00, 0x00]))
        for _ in 0..<RTMPHandshake.sigSize - 8 {
            packet.write(UInt8(arc4random_uniform(0xff)))
        }
        return packet.data
    }

    func c2packet(_ s0s1s2packet: Data) -> Data {
        return ByteArray()
                .writeBytes(s0s1s2packet.subdata(in: 1..<5))
                .write(Int32(Date().timeIntervalSince1970))
                .writeBytes(s0s1s2packet.subdata(in: 9..<RTMPHandshake.sigSize + 1))
                .data
    }

    mutating func clear() {
        timestamp = 0
    }
}
