//
//  MetalVideoRecorder.swift
//  MetalCamera
//
//  Created by Patrick Aubin on 10/7/21.
//  Copyright © 2021 GS. All rights reserved.
//

import Foundation
import AVFoundation

private enum _CaptureState {
    case idle, start, capturing, end
}

class MetalVideoRecorder {
    var isRecording:Bool {
        _captureState == .capturing
    }
    var recordingStartTime = TimeInterval(0)
    private var _captureState = _CaptureState.idle

    private var assetWriter: AVAssetWriter
    private var assetWriterVideoInput: AVAssetWriterInput
    private var assetWriterAudioInput: AVAssetWriterInput?
    private var assetWriterAudioInputFromFile: AVAssetWriterInput?
    private var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    private var completionHandler:(()->())?
    
    private var videoStartTime:CMTime?;
    
    init?(outputURL url: URL, size: CGSize, audioSettings: [String: Any]?) {
        do {
          assetWriter = try AVAssetWriter(outputURL: url, fileType: AVFileType.m4v)
        } catch {
            return nil
        }

        let outputSettings: [String: Any] = [ AVVideoCodecKey : AVVideoCodecType.h264,
            AVVideoWidthKey : size.width,
            AVVideoHeightKey : size.height ]

        assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
        assetWriterVideoInput.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String : size.width,
            kCVPixelBufferHeightKey as String : size.height ]

        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput,
                                                                           sourcePixelBufferAttributes: sourcePixelBufferAttributes)

        assetWriter.add(assetWriterVideoInput)
    }

    func startRecording() {
        switch _captureState {
        case .idle:
            _captureState = .start
        case .capturing:
            _captureState = .end
        default:
            break
        }
    }

    func endRecording(_ completionHandler: @escaping () -> ()) {
        _captureState = .end
        self.completionHandler = completionHandler
    }
    
    func writeSample(sample audioSample: CMSampleBuffer, settings: [String: Any]?, timestamp: TimeInterval, useOtherInput:Bool = false) {
        switch _captureState {
        case .start:
            let scale = CMTimeScale(NSEC_PER_SEC)
            self.videoStartTime = CMTime(value: CMTimeValue(timestamp * Double(scale)), timescale: scale);
            
            assetWriterAudioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
            assetWriterAudioInput!.expectsMediaDataInRealTime = true
            assetWriter.add(assetWriterAudioInput!)
            
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
            
            assetWriterAudioInputFromFile = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
            assetWriterAudioInputFromFile!.expectsMediaDataInRealTime = true
            assetWriter.add(assetWriterAudioInputFromFile!)
            
            assetWriter.startWriting()
            print(CMSampleBufferGetPresentationTimeStamp(audioSample))
            assetWriter.startSession(atSourceTime: .zero) //CMSampleBufferGetPresentationTimeStamp(audioSample)) //CMSampleBufferGetPresentationTimeStamp(audioSample))

            recordingStartTime = CACurrentMediaTime()
            _captureState = .capturing
        case .capturing:
           
            if (self.assetWriter.status == .writing) {
                if (!useOtherInput) {
                    while !self.assetWriterAudioInput!.isReadyForMoreMediaData {}
                    self.assetWriterAudioInput!.append(self.retimeSampleBuffer(sampleBuffer: audioSample, timestamp: timestamp))
                } else {
                    while !self.assetWriterAudioInputFromFile!.isReadyForMoreMediaData {}
                    self.assetWriterAudioInputFromFile!.append(self.retimeSampleBuffer(sampleBuffer: audioSample, timestamp: timestamp))
                }
            }
            
        case .end:
            guard assetWriterAudioInput!.isReadyForMoreMediaData == true, assetWriter.status != .failed else { break }
            guard assetWriterVideoInput.isReadyForMoreMediaData == true, assetWriter.status != .failed else { break }
            if useOtherInput {
                guard self.assetWriterAudioInputFromFile!.isReadyForMoreMediaData == true, assetWriter.status != .failed else { break }
            }
            
            
            assetWriterVideoInput.markAsFinished()
            assetWriter.finishWriting {
                // Move to the idle state once we are done writing
                self._captureState = .idle
                self.assetWriterAudioInput = nil
                self.assetWriterAudioInputFromFile = nil
                if let completionHandler = self.completionHandler {
                    completionHandler()
                }
            }
            
        case .idle:
            break
        }

    }
    
    func retimeSampleBuffer(sampleBuffer: CMSampleBuffer, timestamp: TimeInterval) -> CMSampleBuffer {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count);
        
        var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: CMTimeMake(value: 0, timescale: 0),
                                                                      presentationTimeStamp: CMTimeMake(value: 0, timescale: 0),
                                                                      decodeTimeStamp: CMTimeMake(value: 0, timescale: 0)), count: count)
        
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &info, entriesNeededOut: &count);
        let scale = CMTimeScale(NSEC_PER_SEC)
        
        var currentFrameTime:CMTime = CMTime(value: CMTimeValue(timestamp * Double(scale)), timescale: scale);
        currentFrameTime = currentFrameTime - self.videoStartTime!
        
        for i in 0..<count {
                    info[i].decodeTimeStamp = currentFrameTime
                    info[i].presentationTimeStamp = currentFrameTime
                }
        var soundbuffer:CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                              sampleBuffer: sampleBuffer,
                                              sampleTimingEntryCount: count,
                                              sampleTimingArray: &info,
                                              sampleBufferOut: &soundbuffer);
        return soundbuffer!
    }

    func writeFrame(forTexture texture: MTLTexture) {
        if _captureState != .capturing {
            return
        }

        while !assetWriterVideoInput.isReadyForMoreMediaData {}

        guard let pixelBufferPool = assetWriterPixelBufferInput.pixelBufferPool else {
            print("Pixel buffer asset writer input did not have a pixel buffer pool available; cannot retrieve frame")
            return
        }

        var maybePixelBuffer: CVPixelBuffer? = nil
        let status  = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &maybePixelBuffer)
        if status != kCVReturnSuccess {
            print("Could not get pixel buffer from asset writer input; dropping frame...")
            return
        }

        guard let pixelBuffer = maybePixelBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer)!

        // Use the bytes per row value from the pixel buffer since its stride may be rounded up to be 16-byte aligned
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)

        texture.getBytes(pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        let frameTime = CACurrentMediaTime() - recordingStartTime
        let presentationTime = CMTimeMakeWithSeconds(frameTime, preferredTimescale:   240)
        assetWriterPixelBufferInput.append(pixelBuffer, withPresentationTime: presentationTime)

        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }
    
    func processSampleBuffer(scale: Float, sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var sampleBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
        defer { sampleBytes.deallocate() }
        
        guard checkStatus(CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: sampleBytes), message: "Copying block buffer") else {
            return nil
        }
        
        (0..<length).forEach { index in
            let ptr = sampleBytes + index
            let scaledValue = Float(ptr.pointee) * scale
            let processedValue = Int16(max(min(scaledValue, Float(Int16.max)), Float(Int16.min)))
            ptr.pointee = processedValue
        }
        
        guard checkStatus(CMBlockBufferReplaceDataBytes(with: sampleBytes, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: length), message: "Replacing data bytes in block buffer") else { return nil }
        assert(CMSampleBufferIsValid(sampleBuffer))
        return sampleBuffer
    }

    func checkStatus(_ status: OSStatus, message: String) -> Bool {
        // See: https://www.osstatus.com/
        assert(kCMBlockBufferNoErr == noErr)
        if status != noErr {
            debugPrint("Error: \(message) [\(status)]")
        }
        return status == noErr
    }
}
