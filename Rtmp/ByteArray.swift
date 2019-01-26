//
//  ByteArray.swift
//  Live
//
//  Created by jimlai on 2018/6/6.
//  Copyright © 2018年 jimlai. All rights reserved.
//

import Foundation


enum MsgTypes: UInt8 {
    case chunkSize = 0x1,
    bytesRead   = 0x3,
    ping         = 0x4,
    serverWindow = 0x5,
    peerBandwidth      = 0x6,
    audio        = 0x8,
    video        = 0x9,
    flexStream  = 0xF,
    flexObject  = 0x10,
    flexMessage = 0x11,
    notify       = 0x12,
    sharedObj   = 0x13,
    cmd       = 0x14,
    metaData     = 0x16
}
enum AMFTypes: UInt8 {
    case kAMFNumber = 0,
    kAMFBoolean,
    kAMFString,
    kAMFObject,
    kAMFMovieClip,        /* reserved, not used */
    kAMFNull,
    kAMFUndefined,
    kAMFReference,
    kAMFEMCAArray,
    kAMFObjectEnd,
    kAMFStrictArray,
    kAMFDate,
    kAMFLongString,
    kAMFUnsupported,
    kAMFRecordSet,        /* reserved, not used */
    kAMFXmlDoc,
    kAMFTypedObject,
    kAMFAvmPlus,        /* switch to AMF3 */
    kAMFInvalid = 0xff
}

final class ByteArray {

    var data: Data
    init(_ data: Data? = nil) {
        self.data = data ?? Data()
    }

    @discardableResult
    func write<T>(_ val: T) -> ByteArray where T: FixedWidthInteger {
        var big = val.bigEndian
        let d = Data(bytes: &big,
                     count: MemoryLayout.size(ofValue: big))
        data.append(d)
        return self
    }

    @discardableResult
    func read<T>(_ val: inout T) -> ByteArray where T: FixedWidthInteger {
        val = data.subdata(in: 0 ..< T.bytes).uint()
        data = data.subdata(in: T.bytes ..< data.count)
        return self
    }

    @discardableResult
    func writeBytes(_ d: Data) -> ByteArray {
        data.append(d)
        return self
    }
    @discardableResult
    func writeByte(_ b: AMFTypes) -> ByteArray {
        data.append(b.rawValue)
        return self
    }
    @discardableResult
    func write3(_ val: UInt32) -> ByteArray {
        var big = val.bigEndian
        let d = Data(bytes: &big,
                     count: 3)
        data.append(d)
        return self
    }

    @discardableResult
    func writeStr(_ s: String) -> ByteArray {
        if s.lengthOfBytes(using: .utf8) < 0xffff {
            write(UInt8(AMFTypes.kAMFString.rawValue))
            write(UInt16(s.lengthOfBytes(using: .utf8)))
        }
        else {
            write(UInt8(AMFTypes.kAMFLongString.rawValue))
            write(UInt32(s.lengthOfBytes(using: .utf8)))
        }
        let sd = Data(Array(s.utf8))
        data += sd
        return self
    }

    @discardableResult
    func readStr(_ s: inout String) -> ByteArray {
        var isLongStr: UInt8 = 0
        read(&isLongStr)
        var bytesRead = 0

        if isLongStr == AMFTypes.kAMFString.rawValue {
            var len: UInt16 = 0
            read(&len)
            s = String(data: data.subdata(in: 0 ..< Int(len)), encoding: .utf8) ?? ""
            bytesRead = Int(len)
        }
        else {
            var len: UInt32 = 0
            read(&len)
            s = String(data: data.subdata(in: 0 ..< Int(len)), encoding: .utf8) ?? ""
            bytesRead = Int(len)
        }
        data = data.subdata(in: bytesRead ..< data.count)
        return self
    }

    @discardableResult
    func writeDouble(_ d: Double) -> ByteArray {
        write(UInt8(AMFTypes.kAMFNumber.rawValue))
        write(d.bitPattern)
        return self
    }

    @discardableResult
    func readDouble(_ d: inout Double) -> ByteArray {
        var amfNum: UInt8 = 0
        read(&amfNum)
        var dbs: UInt64 = 0
        read(&dbs)
        d = Double(bitPattern: dbs)
        return self
    }

    @discardableResult
    func writeNum(_ d: UInt8) -> ByteArray {
        writeDouble(Double(d))
        return self
    }

    @discardableResult
    func readNum(_ d: inout UInt8) -> ByteArray {
        var db: Double = 0
        readDouble(&db)
        d = UInt8(db)
        return self
    }

    @discardableResult
    func writeBool(_ b: Bool) -> ByteArray {
        write(UInt8(AMFTypes.kAMFBoolean.rawValue))
        write(b ? UInt8(1) : UInt8(0))
        return self
    }

    @discardableResult
    func writeKey(_ k: String) -> ByteArray {
        let len = UInt16(k.lengthOfBytes(using: .utf8))
        write(len)
        let kd = Data(Array(k.utf8))
        data += kd
        return self
    }

    @discardableResult
    func readKey(_ k: inout String) -> ByteArray {
        var len: UInt16 = 0
        read(&len)
        if let s = String(data: data.subdata(in: 0 ..< Int(len)), encoding: .utf8) {
            k = s
        }
        data = data.subdata(in: Int(len) ..< data.count)
        return self
    }

    @discardableResult
    func writeKS(_ k: String, _ v: String) -> ByteArray {
        writeKey(k)
        writeStr(v)
        return self
    }

    @discardableResult
    func readKS(_ k: inout String, _ v: inout String) -> ByteArray {
        readKey(&k)
        readStr(&v)
        return self
    }

    @discardableResult
    func writeKD(_ k: String, _ v: Double) -> ByteArray {
        writeKey(k)
        writeDouble(v)
        return self
    }
    @discardableResult
    func readKD(_ k: inout String, _ v: inout Double) -> ByteArray {
        readKey(&k)
        readDouble(&v)
        return self
    }

    @discardableResult
    func writeKB(_ k: String, _ v: Bool) -> ByteArray {
        writeKey(k)
        writeBool(v)
        return self
    }

    @discardableResult
    func writeObject(_ cls: (ByteArray) -> ()) -> ByteArray {
        write(UInt8(AMFTypes.kAMFObject.rawValue))
        cls(self)
        write(UInt16(0))
        write(UInt8(AMFTypes.kAMFObjectEnd.rawValue))
        return self
    }

    @discardableResult
    func readObject(_ dict: inout [String: Any]) -> ByteArray {
        guard data.count > 0 else {
            return self
        }
        var amfObj: UInt8 = 0
        read(&amfObj)
        guard amfObj == AMFTypes.kAMFObject.rawValue else {
            return self
        }

        while data.count > 1 {
            let b0 = data[0]
            let b1 = data[1]
            guard b0 != 0 || b1 != 0 else {
                break
            }
            var key = ""
            readKey(&key)
            let type: UInt8 = data.first ?? 0
            var s = ""
            var d: Double = 0
            switch type {
            case AMFTypes.kAMFString.rawValue, AMFTypes.kAMFLongString.rawValue:
                readStr(&s)
                dict[key] = s
            case AMFTypes.kAMFNumber.rawValue:
                readDouble(&d)
                dict[key] = d
            default:
                assert(false, "not supported yet")
            }
        }
        guard data.count >= 3 else {
            assert(false, "unexp")
            return self
        }
        guard data[0] == 0, data[1] == 0, data[2] == AMFTypes.kAMFObjectEnd.rawValue else {
            return self
        }
        data = data.subdata(in: 3 ..< data.count)
        return self
    }
}


