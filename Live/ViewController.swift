//
//  ViewController.swift
//  Live
//
//  Created by jimlai on 2018/5/25.
//  Copyright © 2018年 jimlai. All rights reserved.
//

import UIKit
import AVFoundation
//import HaishinKit
import VideoToolbox
import MetalKit
//let rs = RtmpSessionManager("127.0.0.1", 1935)

let rs = RtmpSessionManager("169.254.161.172", 1935)

final class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var session = AVCaptureSession()
    lazy var preview: AVCaptureVideoPreviewLayer = {
        AVCaptureVideoPreviewLayer(session: session)
    }()
    let queue = DispatchQueue(label: "com.sample.buffer")
    lazy var encoder: Encoder = {
        return Encoder(outputCallback, 640, 480)
    }()
    let gray = Atium("gray")
    let md: MTKDelagate = MTKDelagate()
    @IBOutlet var metalView: MTKView!
    @IBOutlet var cameraView: UIView!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.


        guard let camera = AVCaptureDevice.default(for: .video), let video = try? AVCaptureDeviceInput(device: camera), session.canAddInput(video) else {
            return
        }
        guard let mic = AVCaptureDevice.default(for: .audio), let audio = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audio) else {
            return
        }
        session.addInput(video)
        session.addInput(audio)

        let output = AVCaptureVideoDataOutput()
        let key = (kCVPixelBufferPixelFormatTypeKey as NSString) as String
        let settings = [key: kCVPixelFormatType_32BGRA]
        output.videoSettings = settings
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }


        preview.frame = cameraView.bounds
        cameraView.layer.addSublayer(preview)

        metalView.delegate = md
        metalView.isPaused = true
        metalView.framebufferOnly = true
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.device = Atium.device
        gray ~~> md


        session.startRunning()

        //rs.rd.startHandshake()
        /*
        let rtmpConnection = RTMPConnection()
        let rtmpStream = RTMPStream(connection: rtmpConnection)
        rtmpStream.attachAudio(AVCaptureDevice.default(for: AVMediaType.audio)) { error in
            // print(error)
        }
        rtmpStream.attachCamera(DeviceUtil.device(withPosition: .back)) { error in
            // print(error)
        }

        let hkView = LFView(frame: view.bounds)
        hkView.videoGravity = AVLayerVideoGravity.resizeAspectFill
        hkView.attachStream(rtmpStream)

        // add ViewController#view
        view.addSubview(hkView)

        rtmpConnection.connect("rtmp://169.254.149.71/sg1")
        //rtmpConnection.connect("rtmp://127.0.0.1/sg1")
        rtmpStream.publish("sg1")
        */



    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //connection.videoOrientation = .portrait
        gray.proc(sampleBuffer)

        metalView.draw()
        //encoder.encode(sampleBuffer)

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    //rtmpConnection.connect("rtmp://0678ec.entrypoint.cloud.wowza.com/app-be52")
    //rtmpStream.publish("7b68d1a4")
    /*
 rx ~< {_ in true} >~ {_ in "redux FTW"} >~ redux { (s, vc) in
 print(s)
 }
 rx.rx = "test"
    */
}

