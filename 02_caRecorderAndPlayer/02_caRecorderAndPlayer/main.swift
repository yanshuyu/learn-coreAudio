//
//  main.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2019/12/21.
//  Copyright © 2019 sy. All rights reserved.
//

import Foundation
import CoreGraphics


func handleRecorderError(_ error: CAAudioRecorder.CAAudioRecordeError) {
    switch error {
    case .dataFormatError(let reason):
        print("data ftm error: \(reason)")
    
    case .fileFormatError(let reason):
        print("file ftm error: \(reason)")
        
    case .hardwareError(let reason):
        print("hardware error: \(reason)")
    
    case .bufferError(let reaon):
        print("buffer error: \(reaon)")
        
    case .queueError(let reason):
        print("queue error: \(reason)")
        
    case .codecError(let reason):
        print("codec error: \(reason)")
        
    case .unknowedError:
        print("unknow error")
        
    default:
        print("other error")
    }
}

class RecorderDelegate: CAAudioRecorderDelegate {
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, outputFileURL: URL?, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder finish success: \(finishSuccess)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder stop success: \(stopSuccess)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder pause success: \(pauseSuccess)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder start success: \(startSucces)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder prepare success: \(prepareSuccess)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    

}


do {
    let lpcmRUL = URL(fileURLWithPath: "/Users/sy/Desktop/stdftm_lpcm.caf")
    let aacURL = URL(fileURLWithPath: "/Users/sy/Desktop/stdftm_aac.aac")
    let myRecorderDelegate = RecorderDelegate()
    let myRecoder = try CAAudioRecorder(compressedFormatSettings: nil, outputFileURL: aacURL)
    myRecoder.delegate = myRecorderDelegate
    if myRecoder.prepareToRecord() {
        myRecoder.start()
        print("recording...")
        getchar()
        myRecoder.stop()
    }
    

    
    
    
} catch let error as CAAudioRecorder.CAAudioRecordeError {
    handleRecorderError(error)
}

