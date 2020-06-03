//
//  CAAudioRecorderDelegate.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2020/5/31.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation


protocol CAAudioRecorderDelegate: AnyObject {
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
    func addioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
}

extension CAAudioRecorderDelegate {
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
    func addioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
}



