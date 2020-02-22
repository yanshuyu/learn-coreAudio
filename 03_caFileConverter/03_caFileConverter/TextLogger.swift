//
//  TextLogger.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2020/2/11.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation

class TextLogger: TextOutputStream {
    private var fileHandle: FileHandle?
    
    init?(path: String) {
        // create log file
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
        
        if !FileManager.default.createFile(atPath: path, contents: nil, attributes: nil) {
            return nil
        }
        
        // open log file for writing
        if let fh = FileHandle(forWritingAtPath: path) {
            self.fileHandle = fh
        } else {
            return nil
        }
    }
    
    convenience init?(url: URL) {
        self.init(path: url.path)
    }
    
    deinit {
        close()
    }
    

    public func write(_ string: String) {
        if let fh = self.fileHandle,let utf8Data = string.data(using: .utf8) {
            fh.write(utf8Data)
        }
    }
    
    public func close() {
        if let fh = self.fileHandle {
            try? fh.close()
            self.fileHandle = nil
        }
    }
}
