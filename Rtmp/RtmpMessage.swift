//
//  RtmpMessage.swift
//  Live
//
//  Created by jimlai on 2018/7/27.
//  Copyright © 2018年 jimlai. All rights reserved.
//

import Foundation

enum RtmpMsg {
    case connect, createStream, publish, streamBegin(UInt32), streamEOF(UInt32), streamDry(UInt32), ping(UInt32), pong(UInt32)
    case setChunkSize(UInt32), abort(UInt32), ack(UInt32), winAckSize(UInt32), peerBandwidth(UInt32, UInt8)
    func toMsg(_ msid: UInt32) -> Fmt0? {
        guard let ms = MsgStreams(rawValue: msid) else {
            return nil
        }
        switch self {
        case .setChunkSize(let p), .abort(let p), .ack(let p), .winAckSize(let p):
            return CW.makeMsg(.chunkSize, ms, p.toBigData())
        case .peerBandwidth(let ackWinSize, let limitType):
            let pd = ByteArray()
            pd.write(ackWinSize).write(limitType)
            return CW.makeMsg(.chunkSize, ms, pd.data)
        case .pong(let p):
            let eventType: UInt16 = 0x7
            let pd = ByteArray().write(eventType).writeBytes(p.toBigData()).data
            return CW.makeMsg(.ping, ms, pd)
        default:
            return nil

        }
    }
}
