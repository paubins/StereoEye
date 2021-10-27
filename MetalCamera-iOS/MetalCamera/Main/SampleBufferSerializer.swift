/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Class `SampleBufferSerializer` implements the player logic that is executed on a serial queue.
*/

import AVFoundation

// In this sample project, the audio player implements a persistent list of tracks that a user can play multiple times.
 
// Your player might not need a persistent list of tracks. For example, a streaming player might need only a temporary
// queue of items, where you remove items from the queue as soon as their playback ends. In that case, you can ignore
// the `SampleBufferPlayer` class, and use only the `SampleBufferSerializer` class, eliminating the complexity of making
// the playlist editable.
 
// You pass `SampleBufferSerializer` a complete queue of items to play. If you wish to play a different or rearranged
// queue, you must construct that queue yourself. You pass the queue to one of the following public methods of
// `SampleBufferSerializer`:
 
// • `restartQueue(with:atOffset:)` — Stops any current playback and restarts playback with the specified list of items.
 
// • `continueQueue(with:)` — Continues playback of any identical items at the start of both the playing list and the
//   specified list. It then finishes playback with nonidentical items from the specified list.
 
// In this scenario, items in the queue must each have a unique identification, so the queue actually consists of unique
// `SampleBufferItem` values that wrap (possibly nonunique) `PlaylistItem` values. To create a `SampleBufferItem` value
// from a `PlaylistItem` value, use the `sampleBufferItem(playlistItem:fromOffset:)` method of `SampleBufferSerializer`.
class SampleBufferSerializer {
    
    // Notifications for playback events.
    static let currentOffsetKey = "SampleBufferSerializerCurrentOffsetKey"

    static let currentOffsetDidChange = Notification.Name("SampleBufferSerializerCurrentOffsetDidChange")
    static let currentItemDidChange = Notification.Name("SampleBufferSerializerCurrentItemDidChange")
    static let playbackRateDidChange = Notification.Name("SampleBufferSerializerPlaybackRateDidChange")
    
    // Private observers.
    private var periodicTimeObserver: Any!
    private var automaticFlushObserver: NSObjectProtocol!
    
    // The serial queue on which all non-public methods of this class must execute.
    private let serializationQueue = DispatchQueue(label: "sample.buffer.player.serialization.queue")

    // The playback infrastructure.
    private let audioRenderer = AVSampleBufferAudioRenderer()
    private let renderSynchronizer = AVSampleBufferRenderSynchronizer()
    
    // The index of the item in "items" that is currently providing sample buffers.
    // Note that buffers can be enqueued "ahead" from multiple items.
    private var enqueuingIndex = 0
    
    // The playback time, relative to the synchronizer timeline, up to the start of the current item,
    // of the buffers enqueued so far.
    private var enqueuingPlaybackEndTime = CMTime.zero
    
    // The playback time offset, in the current item, of the buffers enqueued so far.
    // Note that the total of `enqueuingPlaybackEndTime + enqueuingPlaybackEndOffset` represents the
    // end time of all playback enqueued so far, in terms of the synchronizer's timeline.
    private var enqueuingPlaybackEndOffset = CMTime.zero
    
    // Initializes a sample buffer serializer.
    init() {
        
        renderSynchronizer.addRenderer(audioRenderer)
        
        // Start generating automatic flush notifications on the serializer thread.
        automaticFlushObserver = NotificationCenter.default.addObserver(forName: .AVSampleBufferAudioRendererWasFlushedAutomatically,
                                                                        object: audioRenderer,
                                                                        queue: nil) { [unowned self] notification in
            
            self.serializationQueue.async {
                
                // If possible, restart from the point at which audio was interrupted
                // by the flush.
                let restartTime = (notification.userInfo?[AVSampleBufferAudioRendererFlushTimeKey] as? NSValue)?.timeValue
            }
        }
    }
    
    // A helper method that provides more sample buffers when the renderer asks for more,
    // with an optional time limit on how much data will be provided.
    /// - Tag: ProvideMedia
    private func provideMediaData(for limitedTime: CMTime? = nil, sampleBuffer: CMSampleBuffer) {
        var remainingTime = limitedTime
        while audioRenderer.isReadyForMoreMediaData {
            
            // Stop providing data when the requested time limit is exceeded.
            guard remainingTime != .invalid else { break }
            
            // Adjust the presentation time of this sample buffer from item-relative to playback-relative.
            let pts = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
            if let time = remainingTime {
                let duration = CMSampleBufferGetDuration(sampleBuffer)
                remainingTime = duration >= time ? .invalid : time - duration
            }
            CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, newValue: pts)
            
            // Feed the sample buffer to the renderer.
            audioRenderer.enqueue(sampleBuffer)
        }
    }
    
    // A helper method that sends a periodic time offset update notification.
    private func notifyTimeOffsetChanged(from baseTime: CMTime) {
        
        let offset = renderSynchronizer.currentTime() - baseTime
        let userInfo = [SampleBufferSerializer.currentOffsetKey: NSValue(time: offset)]
        
        NotificationCenter.default.post(name: SampleBufferSerializer.currentOffsetDidChange, object: self, userInfo: userInfo)
    }
    


}

// This extension to the SampleBufferSerializer class adds some useful logging methods.
extension SampleBufferSerializer {
    
    enum LogComponentType {
        
        case player, serializer, enqueuer
        
        var description: String {
            
            switch self {
            case .player:     return "sb player    "
            case .serializer: return "sb serializer"
            case .enqueuer:   return "sb enqueuer  "
            }
        }
    }
    
    /// - Tag: ControlLogging
    private static var shouldLogEnqueuerMessages = true
    
    func printLog(component: LogComponentType, message: String, at time: CMTime? = nil) {
        
        guard component != .enqueuer || SampleBufferSerializer.shouldLogEnqueuerMessages else { return }
        
        let componentString = "**** " + component.description + " ****"
        let timestamp = String(format: "  %09.4f", renderSynchronizer.currentTime().seconds)
        print(componentString, timestamp, message + printLogTime(time))
    }
    
    private func printLogTime(_ time: CMTime?) -> String {
        guard let time = time else { return "" }
        return String(format: "%.4f", time.seconds)
    }
    
}
