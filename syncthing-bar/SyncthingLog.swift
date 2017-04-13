//
//  SyncthingLog.swift
//  syncthing-bar
//
//  Created by Andreas Streichardt on 15.12.14.
//  Copyright (c) 2014 mop. All rights reserved.
//

import Foundation

open class SyncthingLog {
    var logBuffer : Array<String> = []
    
    public init() {
    }
    
    func log(_ line: String) {
        logBuffer.append(line)
        if logBuffer.count >= 10000 {
            logBuffer.remove(at: 0)
        }
    }
}
