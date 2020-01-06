//
//  main.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2019/12/21.
//  Copyright © 2019 sy. All rights reserved.
//

import Foundation
import CoreGraphics

class RecorderDelegate: CAAudioRecorderDelegate {
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: Error?) {
        print("recoder prepare success: \(prepareSuccess), error: \(error?.localizedDescription ?? "nil")")
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: Error?) {
        print("recorder start record success: \(startSucces), error: \(error?.localizedDescription ?? "nil")")
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: Error?) {
        print("recoder pause success: \(pauseSuccess), error: \(error?.localizedDescription ?? "nil")")
    }
    
    func addioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: Error?) {
        print("audio recorder stop success: \(stopSuccess), error:\(error?.localizedDescription ?? "nil")")
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, outputFileURL: URL?, error: Error?) {
        print("recoeder finish success: \(finishSuccess), out file path: \(outputFileURL?.path ?? "nil"), error:\(error?.localizedDescription ?? "nil")")
    }
}

let myRecorderDelegate = RecorderDelegate()
var myRecoder: CAAudioRecorder!
do {
    myRecoder = try CAAudioRecorder(standardFormatWithChannelCount: 2)
} catch {
    print("create recoder error: \(error.localizedDescription)")
}
myRecoder.delegate = myRecorderDelegate

if myRecoder.prepareToRecord() {
    myRecoder.start()
    print("recording....(press any key to exit)")
    getchar()
    myRecoder.stop()
} else {
    print("recorder prepare failed!")
}


