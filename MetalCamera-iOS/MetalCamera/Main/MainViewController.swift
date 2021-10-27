//
//  MainViewController.swift
//  MetalCamera
//
//  Created by Greg on 24/07/2019.
//  Copyright © 2019 GS. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMedia
import ARKit
import Photos
import AVFAudio
import AudioToolbox

extension AVAudioPCMBuffer {
    func configureSampleBuffer() -> CMSampleBuffer? {
        let audioBufferList = self.mutableAudioBufferList
        let asbd = self.format.streamDescription

        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil
        
        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                         asbd: asbd,
                                                   layoutSize: 0,
                                                       layout: nil,
                                                       magicCookieSize: 0,
                                                       magicCookie: nil,
                                                       extensions: nil,
                                                       formatDescriptionOut: &format);
        if (status != noErr) { return nil; }
        
        var timing: CMSampleTimingInfo = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
                                                            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                                            decodeTimeStamp: CMTime.invalid)
        status = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                      dataBuffer: nil,
                                      dataReady: false,
                                      makeDataReadyCallback: nil,
                                      refcon: nil,
                                      formatDescription: format,
                                      sampleCount: CMItemCount(self.frameLength),
                                      sampleTimingEntryCount: 1,
                                      sampleTimingArray: &timing,
                                      sampleSizeEntryCount: 0,
                                      sampleSizeArray: nil,
                                      sampleBufferOut: &sampleBuffer);
        if (status != noErr) { NSLog("CMSampleBufferCreate returned error: \(status)"); return nil }
        
        status = CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer!,
                                                                blockBufferAllocator: kCFAllocatorDefault,
                                                                blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                                flags: 0,
                                                                bufferList: audioBufferList);
        if (status != noErr) { NSLog("CMSampleBufferSetDataBufferFromAudioBufferList returned error: \(status)"); return nil; }
        
        return sampleBuffer
    }
    
    static func create(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        
        guard let description: CMFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let sampleRate: Float64 = description.audioStreamBasicDescription?.mSampleRate,
              let channelsPerFrame: UInt32 = description.audioStreamBasicDescription?.mChannelsPerFrame /*,
         let numberOfChannels = description.audioChannelLayout?.numberOfChannels */
        else { return nil }
        
        guard let blockBuffer: CMBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        let samplesCount = CMSampleBufferGetNumSamples(sampleBuffer)
        
        //let length: Int = CMBlockBufferGetDataLength(blockBuffer)
        
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(1), interleaved: false)
        
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat!, frameCapacity: AVAudioFrameCount(samplesCount))!
        buffer.frameLength = buffer.frameCapacity
        
        // GET BYTES
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &dataPointer)
        
        guard var channel: UnsafeMutablePointer<Float> = buffer.floatChannelData?[0],
              let data = dataPointer else { return nil }
        
        var data16 = UnsafeRawPointer(data).assumingMemoryBound(to: Int16.self)
        
        for _ in 0...samplesCount - 1 {
            channel.pointee = Float32(data16.pointee) / Float32(Int16.max)
            channel += 1
            for _ in 0...channelsPerFrame - 1 {
                data16 += 1
            }
            
        }
        
        return buffer
    }
}

public extension FileManager {

    func temporaryFileURL(fileName: String = UUID().uuidString) -> URL? {
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(fileName)
    }
}

class Caller {
    var asset:AVAsset!
    var assetReader:AVAssetReader!
    var audioAssetReaderOutput:AVAssetReaderTrackOutput!
    var videoAssetReaderOutput:AVAssetReaderTrackOutput!
    
    init(filename: String, fileExtension: String) {
        self.loadAsset(name: filename, fileExtension: fileExtension)
    }
    
    func getVideoBuffer() -> CVImageBuffer? {
        if let buffer = videoAssetReaderOutput.copyNextSampleBuffer() {
            return CMSampleBufferGetImageBuffer(buffer)
        }
        return nil
    }
    
    func getAudioBuffer() -> AVAudioPCMBuffer? {
        if let buffer = audioAssetReaderOutput.copyNextSampleBuffer(),
            let sample =  AVAudioPCMBuffer.create(from: buffer) {
            return sample
        }
        return nil
    }
    
    fileprivate func loadAsset(name: String, fileExtension: String) {
        self.asset = AVAsset(url: Bundle.main.url(forResource: name, withExtension: fileExtension)!)
        self.assetReader = try! AVAssetReader(asset: asset)
        
        DispatchQueue(label: "loadtracks").async {
            var channelLayout = AudioChannelLayout()
            memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size);
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
            
            let outputSettings:[String : Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVChannelLayoutKey: NSData(bytes:&channelLayout, length:  MemoryLayout.size(ofValue: AudioChannelLayout.self)),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                
            ]
            
            // load the asset from the library
            self.asset.loadValuesAsynchronously(forKeys: ["tracks"], completionHandler: {
                if let assetTrack = self.asset.tracks(withMediaType: .audio).first {
                    self.audioAssetReaderOutput = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: outputSettings)
                    self.assetReader.add(self.audioAssetReaderOutput)
                    
                }
                
                if let videoAssetTrack = self.asset.tracks(withMediaType: .video).first {
                    let videoReaderSettings : [String : Int] = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
                    self.videoAssetReaderOutput = AVAssetReaderTrackOutput(track: videoAssetTrack, outputSettings: videoReaderSettings)
                    self.assetReader.add(self.videoAssetReaderOutput)
                }
                
                self.assetReader.startReading()
            })
        }
    }
}

class Call : NSObject {
    private var recorder:MetalVideoRecorder?
    
    private var fileURL: URL?
    private var audioCapture = AudioCapture()
    private var synth = Synthesizer()
    
    private var audioEngine: AVAudioEngine = AVAudioEngine()
    private var mixer: AVAudioMixerNode = AVAudioMixerNode()
    
    private var audioPlayer:AVAudioPlayerNode!
    private var audioPlayer2:AVAudioPlayerNode!
    
    private var caller:Caller!
    private var caller2:Caller!
    
    var session: ARSession!
    var configuration = ARWorldTrackingConfiguration()
    
    lazy var displayLink: CADisplayLink = {
        let dl = CADisplayLink(target: self, selector: #selector(readBuffer(_:)))
        dl.add(to: .current, forMode: .default)
        dl.isPaused = true
        return dl
    }()
    
    private var playbackCallback:((CVImageBuffer, CVImageBuffer) -> ())!
    private var recordingCallback:((MTLTexture) -> ())!
    
    init(filename1: [String], filename2: [String],
         playbackCallback: @escaping (CVImageBuffer, CVImageBuffer) -> (),
         recordingCallback: @escaping (MTLTexture) -> ()) {
        super.init()
        
        caller = Caller(filename: filename1[0], fileExtension: filename1[1])
        caller2 = Caller(filename: filename2[0], fileExtension: filename2[1])
        
        // do work in a background thread
        DispatchQueue(label: "queue-audio").async {
            
            
            self.audioPlayer = AVAudioPlayerNode()
            self.audioPlayer2 = AVAudioPlayerNode()
        }
        
        
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 23, maximum: 30, preferred: 30)
        } else {
            // Fallback on earlier versions
            displayLink.frameInterval = 1
        }
        displayLink.isPaused = true
        
        self.playbackCallback = playbackCallback
        self.recordingCallback = recordingCallback
        
        // Set this view controller as the session's delegate.
        session = ARSession()
        session.delegate = self
        
        // Enable the smoothed scene depth frame-semantic.
        configuration.frameSemantics = .sceneDepth
        
        // Run the view's session.
//        session.run(configuration)
    }
    
    func getBuffer1() -> CVImageBuffer? {
        return self.caller.getVideoBuffer()
    }
    
    func getBuffer2() -> CVImageBuffer? {
        return self.caller2.getVideoBuffer()
    }
    
    func record() {
        guard !self.audioPlayer.isPlaying else {
            self.audioPlayer.stop()
            self.audioPlayer2.stop()
            displayLink.isPaused = true
            
            if let recorder = self.recorder {
                if recorder.isRecording {
                    recorder.endRecording {
                        self.audioCapture.stop()
                        let status = PHPhotoLibrary.authorizationStatus()

                        //no access granted yet
                        if status == .notDetermined || status == .denied {
                            PHPhotoLibrary.requestAuthorization({auth in
                                if auth == .authorized{
                                    self.saveInPhotoLibrary(self.fileURL!)
                                }else{
                                    print("user denied access to photo Library")
                                }
                            })

                        //access granted by user already
                        }else{
                            self.saveInPhotoLibrary(self.fileURL!)
                        }
                        
                        print("ended recording")
                        
                        self.recorder = nil
                    }
                }
            }
            
            return
        }

        DispatchQueue(label: "queue-audio").async {
            self.audioEngine.attach(self.mixer)
            self.audioEngine.attach(self.audioPlayer)
            self.audioEngine.attach(self.audioPlayer2)
            
            if let sampleBuffer = self.caller.getAudioBuffer() {
                
              // Notice the output is the mixer in this case
                self.audioEngine.connect(self.audioPlayer,
                                         to: self.mixer,
                                         format: sampleBuffer.format)
                
                self.audioPlayer.scheduleBuffer(sampleBuffer) {
                    print("queued")
                }
                
            }
            
            if let sampleBuffer = self.caller2.getAudioBuffer() {
                
              // Notice the output is the mixer in this case
                self.audioEngine.connect(self.audioPlayer2,
                                         to: self.mixer,
                                         format: sampleBuffer.format)
                
                self.audioPlayer2.scheduleBuffer(sampleBuffer) {
                    print("queued")
                }
                
                
                self.audioEngine.connect(self.mixer,
                                         to: self.audioEngine.outputNode,
                                         format: self.audioEngine.mainMixerNode.outputFormat(forBus: 0))
                // !important - start the engine *before* setting up the player nodes
                self.mixer.installTap(onBus: 0, bufferSize: 4410,
                                                          format: self.audioEngine.mainMixerNode.outputFormat(forBus: 0), block: { buffer, time in
                    print(time)
                    buffer.configureSampleBuffer()
                })
                
                self.audioEngine.prepare()
                try! self.audioEngine.start()
            }
            
            self.audioPlayer.play()
            self.audioPlayer2.play()
        }
        
        displayLink.isPaused = false
        
        return;
        
        // let's not record just yet
        self.fileURL = FileManager.default.temporaryFileURL(fileName: "temp.m4v")
        self.recorder = MetalVideoRecorder(outputURL: fileURL!,
                                                     size: CGSize(width: UIScreen.main.bounds.size.width,
                                                                  height: UIScreen.main.bounds.size.height),
                                                     audioSettings: self.audioCapture.preferredSettings(for: AVFileType.m4v))
        
        self.recorder!.startRecording()
        self.audioCapture.delegate = self
        self.audioCapture.setUp(sessionPreset: .medium) { completed in
            print(completed)
        }
        self.audioCapture.start()
    }
    
    
    @objc private func readBuffer(_ sender: CADisplayLink) {
        if let sampleBuffer = self.getBuffer1(), let sampleBuffer2 = self.getBuffer2() {
            self.playbackCallback(sampleBuffer, sampleBuffer2)
        }
        
        if self.audioPlayer.isPlaying, let sampleBuffer = self.caller.getAudioBuffer() {
            self.audioPlayer.scheduleBuffer(sampleBuffer) {
                print("queued")
            }
        }
        
        if self.audioPlayer2.isPlaying, let sampleBuffer = self.caller2.getAudioBuffer() {
            self.audioPlayer2.scheduleBuffer(sampleBuffer) {
                print("queued")
            }
        }
        
//        if let recorder = self.metalView.recorder, recorder.isRecording {
//            let sampleBuffer = self.audioSamples.removeFirst()
//            self.metalView.recorder?.writeSample(sample: sampleBuffer,
//                                                 settings: self.audioCapture.preferredSettings(for: AVFileType.m4v),
//                                                 timestamp: self.session.currentFrame!.timestamp,
//                                                 useOtherInput: true)
//        }
    }
    
    private func saveInPhotoLibrary(_ url:URL){
        PHPhotoLibrary.shared().performChanges({

            //add video to PhotoLibrary here
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { completed, error in
            if completed {
                print("save complete! path : " + url.absoluteString)
                do {
                    try FileManager.default.removeItem(at: self.fileURL!)
                } catch {
                    print("nothing to remove")
                }
            }else{
                print("save failed")
            }
        }
    }
    
    func writeFrame(texture: MTLTexture) {
        if let recorder = self.recorder, recorder.isRecording {
            recorder.writeFrame(forTexture: texture)
        }
    }
}

extension Call: AudioVideoCaptureDelegate {
    
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        DispatchQueue.main.async {

        }
    }
    
    func audioCapture(_ capture: AudioCapture, didCaptureSample: CMSampleBuffer) {
        print("captured")
        self.recorder?.writeSample(sample: didCaptureSample,
                                             settings: self.audioCapture.preferredSettings(for: AVFileType.m4v),
                                             timestamp: self.session.currentFrame!.timestamp)
    }
}

extension Call : ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let depthMap = frame.sceneDepth?.depthMap
        else { return }
        
        DispatchQueue.main.async {
//            self.metalView.pixelBuffer = frame.capturedImage
        }
    }
}

final class MainViewController: UIViewController, ARSessionDelegate {
    @IBOutlet weak var metalView: MetalView!

    @IBOutlet weak var cycleTextures: UIButton!
    var showDepth:Bool = false
    var call:Call!
    
    @IBOutlet weak var recordButton: UIButton!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // The screen shouldn't dim during AR experiences.
        UIApplication.shared.isIdleTimerDisabled = true
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                
            } else {
                // Present message to user indicating that recording
                // can't be performed until they change their preference
                // under Settings -> Privacy -> Microphone
            }
        }
        
        self.call = Call(filename1: ["farucca", "mp4"],
                         filename2: ["dua_lipa", "mp4"]) { sampleBuffer, sampleBuffer2 in
            self.metalView.mainCallerPixelBuffer = sampleBuffer
            self.metalView.secondaryCallerPixelBuffer = sampleBuffer2
        } recordingCallback: { texture in
            print("unused")
        }
        
        self.metalView.bufferCallback = { texture in
            self.call.writeFrame(texture: texture)
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    @IBAction func cycleTextures(_ sender: Any) {
        let alertController = UIAlertController(title: "About", message: "Combines depth camera and autostereograms(more commonly known as Magic Eyes)", preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Okay", style: .default, handler: { action in
            print("cool")
        }))
        self.present(alertController, animated: true) {
            print("presented")
        }
    }
    
    @IBAction func cycleTexturesAction(_ sender: Any) {
//        self.metalView.showDepth = !self.metalView.showDepth
        print("playing")
        self.call.record()
    }
}
