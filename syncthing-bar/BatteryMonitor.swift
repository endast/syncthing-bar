//
//  BatteryMonitor.swift
//  syncthing-bar
//
//  Created by Sascha Hagedorn on 09/06/16.
//  Copyright © 2016 mop. All rights reserved.
//

import Foundation

class BatteryMonitor: NSObject {
    var timer_interval: Double
    var monitorTimer : Timer?
    var notificationCenter: NotificationCenter = NotificationCenter.default
    
    override init() {
        self.timer_interval = 4.0
        
        super.init()
    }
    
    func startMonitor() {
        if (monitorTimer != nil && monitorTimer!.isValid) {
            return
        }
    
        monitorTimer = Timer.scheduledTimer(timeInterval: self.timer_interval,
                                                              target: self,
                                                              selector: #selector(BatteryMonitor.checkBattery(_:)),
                                                              userInfo: nil,
                                                              repeats: true)
    }
    
    func stopMonitor() {
        if (monitorTimer != nil && monitorTimer!.isValid) {
            monitorTimer!.invalidate()
        }
    }
    
    func checkBattery(_ timer: Timer) {
        if (!timer.isValid) {
            return
        }
        
        let startStopData = ["pause" : isOnBattery()]
        notificationCenter.post(name: Notification.Name(rawValue: StartStop), object: self, userInfo: startStopData)
    }
    
    func isOnBattery() -> Bool {
        let timeRemaining: CFTimeInterval = IOPSGetTimeRemainingEstimate()
        
        if timeRemaining == -2.0 {
            return false
        }
        
        return true
    }
}
