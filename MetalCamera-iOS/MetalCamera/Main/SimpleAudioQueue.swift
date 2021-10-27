//
//  SimpleAudioQueue.swift
//  MetalCamera
//
//  Created by Patrick Aubin on 10/22/21.
//  Copyright © 2021 GS. All rights reserved.
//

import Foundation
import AudioToolbox
import CoreMedia
import AVFAudio

func synthesizerCallback(userData: UnsafeMutableRawPointer?, audioQueue: AudioQueueRef, buffer: AudioQueueBufferRef) {
    guard let rawSynth = userData else { return }
    let synth = Unmanaged<Synthesizer>.fromOpaque(rawSynth).takeUnretainedValue()
//    guard synth.samples.count > 0 else { return }
    let audioSample:CMSampleBuffer = synth.samples[0]
    synth.write(audioSample: audioSample, withAudioQueue: audioQueue, toBuffer: buffer)
    print("writing sample")
}

class Synthesizer {

    enum Errors: Error {
        case coreAudioError(OSStatus)
        case couldNotInitialiseAudioQueue
    }

    private var format: AudioStreamBasicDescription
    private var outputQueue: AudioQueueRef?
    private var outputBuffers: [AudioQueueBufferRef?]
    private var offset: Double = 0
    
    let semaphore = DispatchSemaphore(value: 1)
    
    var samples:[CMSampleBuffer] = []

    let sampleRate: Double
    let channels: Int
    
    private let pcmBufferPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1024)

    init(sampleRate: Double = 44100, channels: Int = 2, bufferCount: Int = 30000) {
        assert(bufferCount > 2, "Need at least three buffers!")

        self.sampleRate = sampleRate
        self.channels = channels
        self.outputBuffers = Array<AudioQueueBufferRef?>(repeating: nil, count: bufferCount)

        let uChannels = UInt32(channels)
        let channelBytes = UInt32(MemoryLayout<Int16>.size)
        let bytesPerFrame = uChannels * channelBytes

        self.format = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: uChannels,
            mBitsPerChannel: channelBytes * 8,
            mReserved: 0
        )
        
       let unsafeRawPointer = UnsafeMutableRawPointer.allocate(byteCount: 4, alignment: 0)
       let audioBuffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: 4, mData: unsafeRawPointer)
       let audioBufferList = AudioBufferList(mNumberBuffers: 0, mBuffers: audioBuffer)
       self.pcmBufferPointer.initialize(repeating: audioBufferList, count: 1024)
    }

    private func createAudioQueue() throws {
        let selfPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        do {
            let createOutputResult = AudioQueueNewOutput(&self.format, synthesizerCallback, selfPointer, CFRunLoopGetCurrent(), nil, 0, &self.outputQueue)

            if createOutputResult != 0 { throw Errors.coreAudioError(createOutputResult) }
            guard let outputQueue = self.outputQueue else { throw Errors.couldNotInitialiseAudioQueue }

            for i in 0 ..< self.outputBuffers.count {
                let bufferSize = Int(Int(self.format.mBytesPerFrame) * (Int(self.format.mSampleRate) / 16))
                let createBufferResult = AudioQueueAllocateBuffer(outputQueue, UInt32(bufferSize), &self.outputBuffers[i])
                if createBufferResult != 0 { throw Errors.coreAudioError(createBufferResult) }
                guard let outputBuffer = self.outputBuffers[i] else { throw Errors.couldNotInitialiseAudioQueue }
                synthesizerCallback(userData: selfPointer, audioQueue: outputQueue, buffer: outputBuffer)
            }
        } catch {
            print(error)
        }
    }
    
    func play() throws {
//        try! AVAudioSession.sharedInstance().setActive(true)
//        try! AVAudioSession.sharedInstance().setCategory(.playback)
        
        try! self.createAudioQueue()
        
        guard let outputQueue = outputQueue else { throw Errors.couldNotInitialiseAudioQueue }
        
        let primeQueueResult = AudioQueuePrime(outputQueue, 0, nil)
        if primeQueueResult != 0 { throw Errors.coreAudioError(primeQueueResult) }

        let startQueueResult = AudioQueueStart(outputQueue, nil)
        if startQueueResult != 0 { throw Errors.coreAudioError(startQueueResult) }
    }

    func write(audioSample: CMSampleBuffer, withAudioQueue audioQueue: AudioQueueRef, toBuffer buffer: AudioQueueBufferRef) {
//        var buffer: AudioQueueBufferRef = nil
        let dataSize = MemoryLayout<Int16>.stride * channels
        let phase = offset / sampleRate * 200 * Double.pi * 2
        let value = Int16(sin(phase) * Double(Int16.max))
        var allChannels = Array<Int16>(repeatElement(value, count: channels))
        
//        let pcmBuffer = AVAudioPCMBuffer.create(from: audioSample)
//        pcmBuffer?.audioBufferList
//
//        let numBytes: UInt32 = buffer.pointee.mAudioDataBytesCapacity
        memcpy(buffer.pointee.mAudioData, &allChannels, Int(dataSize))
//        memcpy(buffer.pointee.mAudioData, &allChannels, Int(dataSize))
//        buffer.pointee.mAudioData.copyMemory(from: &allChannels, byteCount: dataSize)
        buffer.pointee.mAudioDataByteSize = UInt32(dataSize)
        print(buffer)
//
//        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(audioSample, at: 0, frameCount: 1024, into: pcmBufferPointer)
//        if status == 0 {
//            let inputDataPtr: = UnsafeMutableAudioBufferListPointer(pcmBufferPointer)
//            let mBuffers : AudioBuffer = inputDataPtr[0]
//            if let bufferPointer = UnsafeMutableRawPointer(mBuffers.mData){
//                let dataPointer = bufferPointer.assumingMemoryBound(to: Int16.self)
//                let dataArray = Array(UnsafeBufferPointer.init(start: dataPointer, count: 1024))
////                pcmArray.append(contentsOf: dataArray)
//            }else{
////                Logger.log(key: "Audio Sample", message: "Failed to generate audio sample")
//            }
//        }else{
////            Logger.log(key: "Audio Sample", message: "Buffer allocation failed with status \(status)")
//        }
//
//
//
//        return;

//        var audioBufferList = AudioBufferList()
//        var data = Data()
//        var blockBuffer : CMBlockBuffer?
//
//        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(audioSample,
//                                                                bufferListSizeNeededOut: nil,
//                                                                bufferListOut: &audioBufferList,
//                                                                bufferListSize: MemoryLayout<AudioBufferList>.size,
//                                                                blockBufferAllocator: nil,
//                                                                blockBufferMemoryAllocator: nil,
//                                                                flags: 0,
//                                                                blockBufferOut: &blockBuffer)
//
//        let buffers = UnsafeBufferPointer<AudioBuffer>(start: &audioBufferList.mBuffers, count: Int(audioBufferList.mNumberBuffers))
////        sampleBuffer.outputDuration
//        buffer.pointee.mAudioData.copyMemory(from: &audioBufferList.mBuffers.mData,
//                                             byteCount: Int(UInt32(audioBufferList.mBuffers.mDataByteSize)))
//        buffer.pointee.mAudioDataByteSize = UInt32(audioBufferList.mBuffers.mDataByteSize)
////
        
        let enqueueResult = AudioQueueEnqueueBuffer(audioQueue, buffer, 0, nil)
        if enqueueResult != 0 { print(enqueueResult) }
        print(enqueueResult)

        offset += 1
    }

}
