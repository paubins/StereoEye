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

final class MainViewController: UIViewController, ARSessionDelegate {
    @IBOutlet weak var metalView: MetalView!

    var session: ARSession!
    var configuration = ARWorldTrackingConfiguration()
    @IBOutlet weak var cycleTextures: UIButton!
    var showDepth:Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Set this view controller as the session's delegate.
        session = ARSession()
        session.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Enable the smoothed scene depth frame-semantic.
        configuration.frameSemantics = .sceneDepth
        
        // Run the view's session.
        session.run(configuration)
        
        // The screen shouldn't dim during AR experiences.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    @IBAction func cycleTextures(_ sender: Any) {
        
    }
    
    @IBAction func cycleTexturesAction(_ sender: Any) {
        self.metalView.showDepth = !self.metalView.showDepth
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let depthMap = frame.sceneDepth?.depthMap
        else { return }
        
        DispatchQueue.main.async {
            self.metalView.transform = frame.displayTransform(for: .portrait,
                                                              viewportSize: CGSize(width: 256, height: 192))
            self.metalView.pixelBuffer = depthMap 
        }
    }
}

extension MainViewController: VideoCaptureDelegate {
    
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        
        DispatchQueue.main.async {
            self.metalView.pixelBuffer = pixelBuffer
        }
    }
}

