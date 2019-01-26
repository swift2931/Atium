//
//  extensions.swift
//  Live
//
//  Created by jimlai on 2018/7/27.
//  Copyright © 2018年 jimlai. All rights reserved.
//

import Foundation

extension Data {
    func uint<T>(_ big: Bool = true) -> T where T: FixedWidthInteger {
        let t = withUnsafeBytes {$0.pointee} as T
        return big ? t.byteSwapped : t
    }
    mutating func muint<T>(_ start: Int, _ val: T, _ big: Bool = true) where T: FixedWidthInteger {
        withUnsafeMutableBytes { (p: UnsafeMutablePointer<UInt8>) in
            let q = UnsafeMutableRawPointer(p.advanced(by: start))
            let u = q.bindMemory(to: T.self, capacity: MemoryLayout.size(ofValue: val))
            u.pointee = big ? val.bigEndian : val
        }
    }
    func uint24(_ big: Bool = true) -> UInt32 {
        if big {
            return UInt32((self[0] << 16)+(self[1] << 8)+self[2])
        }
        else {
            return UInt32((self[2] << 16)+(self[1] << 8)+self[0])
        }
    }
    private static let hexAlphabet = "0123456789abcdef".unicodeScalars.map { $0 }

    public func hexEncodedString() -> String {
        return String(self.reduce(into: "".unicodeScalars, { (result, value) in
            result.append(Data.hexAlphabet[Int(value/16)])
            result.append(Data.hexAlphabet[Int(value%16)])
        }))
    }

    func bytes<T>(_ at: Int) -> T? where T: FixedWidthInteger {
        guard self.count >= at+T.bitWidth+1 else {
            return nil
        }
        return subdata(in: at ..< at+T.bitWidth).uint()
    }

    func dBytes(_ at: Int) -> Double? {
        guard self.count >= at+8+1 else {
            return nil
        }
        return subdata(in: at ..< at+8).withUnsafeBytes {$0.pointee} as Double
    }
}


extension FixedWidthInteger {
    static var bytes: Int {
        return bitWidth/8
    }
    func toData() -> Data {
        var n = self
        return Data(bytes: &n, count: Self.bytes)
    }
    func toBigData() -> Data {
        var n = self.bigEndian
        return Data(bytes: &n, count: Self.bytes)
    }
}