//
//  VideoCapture.swift
//  MetalCamera
//
//  Created by Greg on 24/07/2019.
//  Copyright © 2019 GS. All rights reserved.
//

import UIKit
import AVFoundation
import CoreVideo

public protocol AudioVideoCaptureDelegate: AnyObject {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame: CVPixelBuffer?, timestamp: CMTime)
    func audioCapture(_ capture: AudioCapture, didCaptureSample: CMSampleBuffer)
}

public class VideoCapture: NSObject {
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public weak var delegate: AudioVideoCaptureDelegate?
    
    let captureSession = AVCaptureSession()
    let videoOutput:AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    let audioOutput:AVCaptureAudioDataOutput = AVCaptureAudioDataOutput()
    let queue = DispatchQueue(label: "camera-queue")
    
    public func setUp(sessionPreset: AVCaptureSession.Preset,
                      frameRate: Int = 0,
                      completion: @escaping (Bool) -> Void) {
        queue.async {
            let success = self.setUpCamera(sessionPreset: sessionPreset, frameRate: frameRate)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func setUpCamera(sessionPreset: AVCaptureSession.Preset, frameRate: Int) -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = sessionPreset
        let desiredFrameRate = frameRate
        
        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            fatalError("Error: no video devices available")
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            fatalError("Error: could not create AVCaptureDeviceInput")
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer.connection?.videoOrientation = .portrait
        self.previewLayer = previewLayer
        
        let settings: [String : Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
        ]
        
        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        videoOutput.connection(with: AVMediaType.video)?.videoOrientation = .portrait
        
        let activeDimensions = CMVideoFormatDescriptionGetDimensions(captureDevice.activeFormat.formatDescription)
        for vFormat in captureDevice.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(vFormat.formatDescription)
            let ranges = vFormat.videoSupportedFrameRateRanges as [AVFrameRateRange]
            if let frameRate = ranges.first,
                frameRate.maxFrameRate >= Float64(desiredFrameRate) &&
                    frameRate.minFrameRate <= Float64(desiredFrameRate) &&
                    activeDimensions.width == dimensions.width &&
                    activeDimensions.height == dimensions.height &&
                    CMFormatDescriptionGetMediaSubType(vFormat.formatDescription) == 875704422 { // full range 420f
                do {
                    try captureDevice.lockForConfiguration()
                    captureDevice.activeFormat = vFormat as AVCaptureDevice.Format
                    captureDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(desiredFrameRate))
                    captureDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(desiredFrameRate))
                    captureDevice.unlockForConfiguration()
                    break
                } catch {
                    continue
                }
            }
        }

        captureSession.commitConfiguration()
        return true
    }
    
    public func start() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }
    
    public func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    public func preferredSettings(for fileType: AVFileType) -> [String: Any]? {
        return self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: fileType)
    }
}

public class AudioCapture : VideoCapture {
    override public func setUp(sessionPreset: AVCaptureSession.Preset,
                      frameRate: Int = 0,
                      completion: @escaping (Bool) -> Void) {
        queue.async {
            let success = self.setUpMicrophone(sessionPreset: sessionPreset, frameRate: frameRate)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    
    func setUpMicrophone(sessionPreset: AVCaptureSession.Preset, frameRate: Int) -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = sessionPreset
        
        guard let audioCaptureDevice = AVCaptureDevice.default(for: AVMediaType.audio) else {
            fatalError("Error: no video devices available")
        }
        
        guard let audioInput = try? AVCaptureDeviceInput(device: audioCaptureDevice) else {
            fatalError("Error: could not create AVCaptureDeviceInput")
        }
        
        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }
        
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        }

        captureSession.commitConfiguration()
        return true
    }
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == self.videoOutput {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            delegate?.videoCapture(self, didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
        } else {
            print("we lookin at an audio sample")
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("captured")
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
//        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        
    }
}

extension AudioCapture : AVCaptureAudioDataOutputSampleBufferDelegate {
    public override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("caught")
        if output == self.audioOutput {
            delegate?.audioCapture(self, didCaptureSample: sampleBuffer)
        }
    }
    
    public override func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("dropped")
    }
}
