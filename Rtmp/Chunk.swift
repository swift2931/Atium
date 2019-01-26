
import Foundation

protocol Chunk {
    var msbMask: UInt32 {get}
    var midMask: UInt32 {get}
    var lsbMask: UInt32 {get}
    var extendedTime: UInt32 {get}
    var msid: UInt32 {get set}
    var data: Data {get}
    var timestamp: UInt32 {get set}
    var type: UInt8 {get set}
    var csid: UInt8 {get set}
    var len: UInt32 {get set}
    var total: Int {get}
    var ecsid: UInt32 {get set}
    var eTimestamp: UInt32 {get}
    var basicHeader: Data {get set}
    var fmt: UInt8 {get set}
    var chunkHeader: Data {get set}
    var payload: Data {get set}
    var etsd: Data {get set}
    static func pChunk() -> Self
    func getTime() -> UInt32
    func getCsid() -> UInt32
}

extension Chunk {
    var msbMask: UInt32 {
        return 0x00ff0000
    }
    var midMask: UInt32 {
        return 0x0000ff00
    }
    var lsbMask: UInt32 {
        return 0x000000ff
    }
    var extendedTime: UInt32 {
        return 0x00ffffff
    }
    var fmt: UInt8 {
        get {
            return (basicHeader[0] & 0xc0) >> 6
        }
        set {
            basicHeader[0] = (0 << 6) + UInt8(csid)
        }
    }
    var csid: UInt8 {
        get {
            return UInt8(basicHeader[0] & 0x3f)
        }
        set {
            basicHeader[0] = (fmt << 6) + newValue
            if newValue > 1 {
                ecsid = 0
            }
        }
    }
    var ecsid: UInt32 {
        get {
            let vlen = csid == 0 ? 2 : csid == 1 ? 3 : 1
            guard basicHeader.count == vlen else {
                return 0
            }
            return csid == 0 ? UInt32(basicHeader[1] + 64) : csid == 1 ? UInt32((basicHeader[2] << 8) + basicHeader[1] + 64) : 0
        }
        set {
            let vlen = csid == 0 ? 2 : csid == 1 ? 3 : 1
            guard basicHeader.count == vlen else {
                return
            }
            if csid == 0 {
                basicHeader[1] = UInt8(newValue - 64)
            }
            if csid == 1 {
                let v = newValue - 64
                basicHeader[1] = UInt8(v%16)
                basicHeader[2] = UInt8(v/16)
            }
        }
    }
    var timestamp: UInt32 {
        get {
            return chunkHeader.subdata(in: 0 ..< 3).uint24()
        }
        set {
            chunkHeader[0] = UInt8((newValue & msbMask) >> 16)
            chunkHeader[1] = UInt8((newValue & midMask) >> 8)
            chunkHeader[2] = UInt8(newValue & lsbMask)
        }
    }
    var total: Int {
        return basicHeader.count + chunkHeader.count + etsd.count + payload.count
    }

    var eTimestamp: UInt32 {
        return timestamp == extendedTime ? etsd.uint() : 0
    }

    var data: Data {
        return basicHeader + chunkHeader + etsd + payload
    }

    func getTime() -> UInt32 {
        return timestamp == extendedTime ? eTimestamp : timestamp
    }

    func getCsid() -> UInt32 {
        return (csid == 0 || csid == 1) ? ecsid : UInt32(csid)
    }
}

struct Fmt0: Chunk {
    var msid: UInt32 {
        get {
            return chunkHeader.subdata(in: 7 ..< 11).uint(false)
        }
        set {
            chunkHeader.muint(7, newValue, false)
        }
    }

    var type: UInt8 {
        get {
            dp("msg type", chunkHeader[6])
            return chunkHeader[6]
        }
        set {
            chunkHeader[6] = newValue
        }
    }

    var len: UInt32 {
        get {
            return UInt32((chunkHeader[3] << 16) + (chunkHeader[4] << 8) + chunkHeader[5])
        }
        set {
            chunkHeader[3] = UInt8((newValue & msbMask) >> 16)
            chunkHeader[4] = UInt8((newValue & midMask) >> 8)
            chunkHeader[5] = UInt8(newValue & lsbMask)
        }
    }

    var basicHeader: Data
    var chunkHeader = Data(count: 11)
    var payload = Data(count: 0)
    var etsd = Data(count: 0)

    var eventType: UInt16? {
        guard payload.count >= 2 else {
            return nil
        }
        return payload.subdata(in: 0 ..< 2).uint()
    }

    func getEventData<T>() -> T? where T: FixedWidthInteger {
        let expectedBytes = T.bytes
        guard payload.count >= expectedBytes else {
            return nil
        }
        return payload.subdata(in: 2 ..< 2+T.bytes).uint()
    }

    // first 4 bytes in payload
    var p4: UInt32 {
        guard payload.count >= 4 else {
            return 0
        }
        return payload.subdata(in: 0 ..< 4).uint()
    }


    init(_ split: ChunkSplit) {
        (basicHeader, chunkHeader, etsd, payload, _) = split
    }

    init(_ bh: Data, _ ch: Data, _ payload: Data, _ etsd: Data = Data()) {
        basicHeader = bh
        chunkHeader = ch
        self.etsd = etsd
        self.payload = payload
    }

    static func pChunk() -> Fmt0 {
        let bh = Data(bytes: [0])
        let ch = Data(bytes: [UInt8](repeating: 0, count: 11))
        let payload = Data()
        return Fmt0(bh, ch, payload)
    }

}

struct Fmt1: Chunk {

    var msid: UInt32

    var type: UInt8 {
        get {
            return chunkHeader[6]
        }
        set {
            chunkHeader[6] = newValue
        }
    }

    var len: UInt32 {
        get {
            return UInt32((chunkHeader[3] << 16) + (chunkHeader[4] << 8) + chunkHeader[5])
        }
        set {
            chunkHeader[3] = UInt8((newValue & msbMask) >> 16)
            chunkHeader[4] = UInt8((newValue & midMask) >> 8)
            chunkHeader[5] = UInt8(newValue & lsbMask)
        }
    }


    var basicHeader: Data
    var chunkHeader = Data(count: 7)
    var payload = Data(count: 0)
    var etsd = Data(count: 0)

    init(_ msid: UInt32, _ timestamp: UInt32, _ split: ChunkSplit) {
        var delta: UInt32 = 0
        (basicHeader, chunkHeader, etsd, payload, delta) = split
        self.msid = msid
        self.timestamp = timestamp + delta
    }

    init(_ bh: Data, _ ch: Data, _ payload: Data, _ etsd: Data = Data()) {
        basicHeader = bh
        chunkHeader = ch
        self.etsd = etsd
        self.payload = payload
        self.msid = 0
        self.timestamp = 0
    }

    static func pChunk() -> Fmt1 {
        let bh = Data(bytes: [1 << 6])
        let ch = Data(bytes: [UInt8](repeating: 0, count: 7))
        let payload = Data()
        return Fmt1(bh, ch, payload)
    }

}
struct Fmt2: Chunk {
    var msid: UInt32

    var type: UInt8

    var len: UInt32

    var basicHeader: Data
    var chunkHeader = Data(count: 3)
    var payload = Data(count: 0)
    var etsd = Data(count: 0)


    init(_ msid: UInt32, _ timestamp: UInt32, _ len: UInt32, _ type: UInt8, _ split: ChunkSplit) {
        var delta: UInt32 = 0
        (basicHeader, chunkHeader, etsd, payload, delta) = split
        self.msid = msid
        self.len = len
        self.type = type
        self.timestamp = timestamp + delta
    }
    init(_ bh: Data, _ ch: Data, _ payload: Data, _ etsd: Data = Data()) {
        basicHeader = bh
        chunkHeader = ch
        self.etsd = etsd
        self.payload = payload
        self.msid = 0
        self.len = 0
        self.type = 0
        self.timestamp = 0
    }

    static func pChunk() -> Fmt2 {
        let bh = Data(bytes: [2 << 6])
        let ch = Data(bytes: [UInt8](repeating: 0, count: 3))
        let payload = Data()
        return Fmt2(bh, ch, payload)
    }
}

struct Fmt3: Chunk {
    var msid: UInt32 = 0

    var type: UInt8 = 0

    var len: UInt32 = 0

    var eTimestamp: UInt32 = 0

    var timestamp: UInt32 = 0

    var basicHeader: Data
    var chunkHeader = Data(count: 0)
    var payload = Data(count: 0)
    var etsd = Data(count: 0)


    init(_ split: ChunkSplit) {
        (basicHeader, chunkHeader, etsd, payload, _) = split
    }

    init(_ bh: Data, _ ch: Data, _ payload: Data, _ etsd: Data = Data()) {
        basicHeader = bh
        chunkHeader = ch
        self.etsd = etsd
        self.payload = payload
    }
    static func pChunk() -> Fmt3 {
        let bh = Data(bytes: [3 << 6])
        let ch = Data()
        let payload = Data()
        return Fmt3(bh, ch, payload)
    }
}


final class CmdReader {
    func parseConnect() {
        resBytes.readObject(&cmdObj).readObject(&resObj)
    }
    func parseCreateStream() {
        resBytes.readObject(&cmdObj).readNum(&streamId)
    }

    static func read(_ pd: Data) -> CmdReader {
        let cr = CmdReader()
        let arr = ByteArray(pd)
        var resStr = ""
        arr.readStr(&resStr).readNum(&cr.tid)
        cr.resBytes = arr
        if resStr == "onStatus" {
            dp("received onStatus")
            cr.onStatus = true
        }
        return cr
    }
    var tid: UInt8 = 0
    var res: String {
        return resObj["code"] as? String ?? ""
    }
    var resBytes = ByteArray()
    var cmdObj = [String: Any]()
    var resObj = [String: Any]()
    var streamId: UInt8 = 0
    var onStatus = false
}

typealias ChunkSplit = (Data, Data, Data, Data, UInt32)
typealias CR = ChunkReader
struct ChunkReader {
    static var chunkSize: UInt32 = 4096
    static var msgs = [UInt32: [UInt32: Chunk]]()
    static var curCSID: UInt32 = 2
    static var curMID: UInt32 = 0
    static var curTime: UInt32 = 0
    static var curLen: UInt32 = 0
    static var curType: UInt8 = 0
    static var sWinAckSize: UInt32 = 0
    static var winAckSize: UInt32 = 0

    static func parse(_ buf: Data, _ handler: (Chunk) -> ()) -> Data {
        var b = buf
        while case let (fmt?, split?, bytesRead) = ChunkReader.splitHeader(b) {
            if let msg = CR.reader(fmt, split) {
                handler(msg)
            }
            b = b.subdata(in: bytesRead ..< b.count)
        }
        return b
    }

    static func reader(_ fmt: UInt8, _ split: ChunkSplit) -> Chunk? {
        var msg: Chunk?
        switch fmt {
        case 0:
            let m0 = Fmt0(split)
            curMID = m0.msid
            curCSID = m0.getCsid()
            curTime = m0.getTime()
            curLen = m0.len
            curType = m0.type
            //msgs[curCSID, default: [UInt32: RtmpMsg]()][curMID] = msg
            msg = m0
        case 1:
            msg = Fmt1(curMID, curTime, split)
        case 2:
            msg = Fmt2(curMID, curTime, curLen, curType, split)
        case 3:
            let m3 = Fmt3(split)
            if let u = msgs[curCSID]?[curMID]?.payload {
                msgs[curCSID]?[curMID]?.payload = u + m3.payload
            }
            msg = m3
        default:
            assert(false, "unexpected fmt")
        }
        return msg
    }
    static func splitHeader(_ data: Data) -> (UInt8?, ChunkSplit?, Int) {
        let extendedTime = 0x00ffffff
        dp(data.count)
        guard data.count > 0 else {
            return (nil, nil, 0)
        }
        let fmt = (data[0] & 0xC0) >> 6
        let csid = data[0] & 0x3f
        var basicHeader = Data()
        var chunkHeader = Data()
        var payload = Data()
        let chSize = fmt == 0 ? 11 : fmt == 1 ? 7 : fmt == 2 ? 3 : 0
        var timestamp: UInt32 = 0
        var etsd = Data()
        let headEnd = csid == 0 ? 2 : csid == 1 ? 3 : 1

        guard data.count >= headEnd+chSize else {
            return (nil, nil, 0)
        }

        basicHeader = data.subdata(in: 0 ..< headEnd)
        chunkHeader = data.subdata(in: headEnd ..< headEnd+chSize)
        timestamp = fmt < 3 ? chunkHeader.subdata(in: 0 ..< 3).uint24() : 0
        let len = fmt <= 1 ? chunkHeader.subdata(in: 3 ..< 6).uint24() : CR.curLen
        let ps = headEnd+chSize
        // assuming msg length <= chunk size for simplicity
        let pe = headEnd+chSize+Int(len)
        let bytesRead = timestamp == extendedTime ? pe+4 : pe
        guard data.count >= bytesRead else {
            return (nil, nil, 0)
        }
        if timestamp == extendedTime {
            etsd = data.subdata(in: ps ..< ps+4)
            payload = data.subdata(in: ps+4 ..< pe+4)
        }
        else {
            payload = data.subdata(in: ps ..< pe)
        }
        return (fmt, (basicHeader, chunkHeader, etsd, payload, timestamp), bytesRead)
    }

}
typealias CW = ChunkWriter

struct ChunkWriter {
    static func pConnect(_ url: String, _ tid: UInt8) -> Data {
        let pd = ByteArray()
        pd.writeStr("connect").writeNum(tid).writeObject { ba in
            ba.writeKS("app", "sg1")
            ba.writeKS("tcUrl", "rtmp://localhost:1935/app/sg1")
            ba.writeKB("fpad", false)
            ba.writeKD("audioCodecs", 0x0400)
            ba.writeKD("videoCodecs", 0x0080)
            //ba.writeKD("videoFunction", 1)
        }
        //dp(pd.data.hexEncodedString())
        return pd.data
    }
    static func pCreateStream(_ tid: UInt8) -> Data {
        let pd = ByteArray()
        pd.writeStr("createStream").writeNum(tid).writeByte(.kAMFNull)
        return pd.data
    }
    static func pPublish(_ tid: UInt8, _ path: String) -> Data {
        let pd = ByteArray()
        pd.writeStr("publish").writeNum(tid).writeByte(.kAMFNull).writeStr(path).writeStr("live")
        return pd.data
    }

    static func pChunkSize(_ size: UInt32 = 4096) -> Data {
        return ByteArray().write(size).data
    }

    static func pVideoHeader(_ avcheader: Data) -> Data {
        let ba = ByteArray()
        ba.write(0x17 as UInt8).write(0 as UInt8).write3(0).writeBytes(avcheader)
        return ba.data
    }
    static func pVideo(_ avc: Data, _ isKey: Bool) -> Data {
        let firstByte: UInt8 = isKey ? 0x17 : 0x27
        let ba = ByteArray()
        ba.write(firstByte).write(1 as UInt8).write3(0).writeBytes(avc)
        return ba.data
    }

    static func makeMsg(_ type: MsgTypes, _ msid: MsgStreams, _ payload: Data, _ csid: UInt8 = 0x09, _ msgLen: UInt32? = nil, _ timestamp: UInt32 = 0) -> Fmt0 {
        var chunk = Fmt0.pChunk()
        //chunk.csid = UInt8(CR.curCSID)
        chunk.csid = csid
        chunk.type = type.rawValue
        chunk.payload = payload
        //dp(payload.count)
        if let len = msgLen {
            chunk.len = len
        }
        else {
            chunk.len = UInt32(payload.count)
        }
        chunk.msid = msid.rawValue
        chunk.timestamp = timestamp
        return chunk
    }
    static func makeMsg<T>(_ msid: MsgStreams, _ csid: UInt8, _ payload: Data, _ delta: UInt32 = 0, _ type: MsgTypes? = nil) -> T where T: Chunk {
        var fmt = T.pChunk()
        switch T.self {
        case is Fmt1.Type:
            guard let type = type else {
                dp("fmt1 not properly set")
                break
            }
            fmt.timestamp = delta
            fmt.len = UInt32(payload.count)
            fmt.type = type.rawValue
        case is Fmt2.Type:
            fmt.timestamp = delta
        default:
            break

        }
        fmt.msid = msid.rawValue
        fmt.csid = csid
        fmt.payload = payload
        return fmt
    }
}
