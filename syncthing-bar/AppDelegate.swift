//
//  AppDelegate.swift
//  syncthing-statusbar
//
//  Created by Andreas Streichardt on 12.12.14.
//  Copyright (c) 2014 Andreas Streichardt. All rights reserved.
//

import Cocoa
import AppKit
// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    //var settingsWindowController = SettingsWindowController() //windowNibName: "Settings")
    var runner : SyncthingRunner?
    var syncthingBar : SyncthingBar?
    var log : SyncthingLog = SyncthingLog()
    var monitor : MonitorRunner?
    var batteryMonitor : BatteryMonitor?
    
    func applicationWillFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(NSApplicationActivationPolicy.accessory)
    }
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        syncthingBar = SyncthingBar(log: log)
        runner = SyncthingRunner(log: log)
        let result = runner!.ensureRunning()
        if (result != nil) {
            let alert = NSAlert()
            alert.addButton(withTitle: "Ok :(")
            alert.messageText = "Got a fatal error: \(result!) :( Exiting"
            alert.alertStyle = NSAlertStyle.warning
            _ = alert.runModal()
            self.quit()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.tooManyErrors(_:)), name: TooManyErrorsNotification, object: runner)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.foldersDetermined(_:)), name: FoldersDetermined, object: runner)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.httpChanged(_:)), name: HttpChanged, object: runner)
        
        self.monitor = MonitorRunner(monitor_apps: syncthingBar?.settings?.monitor_apps)
        if self.syncthingBar!.settings!.monitoring {
            self.monitor?.startMonitor()
        }
        
        self.batteryMonitor = BatteryMonitor()
        if self.syncthingBar!.settings!.pause_on_battery {
            self.batteryMonitor?.startMonitor()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.settingsSet(_:)), name: SettingsSet, object: syncthingBar?.setter)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.startStop(_:)), name: StartStop, object: syncthingBar)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.startStop(_:)), name: StartStop, object: monitor)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.startStop(_:)), name: StartStop, object: batteryMonitor)
    }
    
    func stop() {
        runner?.stop()
    }
    
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // mop: i don't get it .... this will only get called when quitting via UI. SIGTERM will NOT land here and i fail installing a proper signal handler :|
        self.stop()
    }
        
    func settingsAction(_ sender : AnyObject) {
        //settingsWindowController.showWindow(sender)
    }
    
    func quitAction(_ sender : AnyObject) {
        if (syncthingBar!.settings!.confirm_exit) {
            let alert = NSAlert()
            alert.addButton(withTitle: "Yes")
            alert.addButton(withTitle: "Cancel")
            alert.messageText = "Are you sure you want to quit?"
            
            // FIX: THIS DOESN'T WORK ...
            //var remember_btn: NSButton = alert.addButtonWithTitle("Remember my decision.")
            //remember_btn.setButtonType(NSButtonType.OnOffButton)
            
            alert.alertStyle = NSAlertStyle.warning
        
            let response = alert.runModal()
            if (response != NSAlertFirstButtonReturn) {
                return
            }
        }
        self.quit()
    }
    
    func tooManyErrors(_ sender : AnyObject) {
        let alert = NSAlert()
        alert.addButton(withTitle: "Ok :(")
        alert.messageText = "Syncthing could not run. There were too many errors. Check log, and restart :("
        alert.alertStyle = NSAlertStyle.warning
        
        _ = alert.runModal()
    }
    
    func genericError(_ errorMessage: String) {
        let alert = NSAlert()
        alert.addButton(withTitle: "Ok :(")
        alert.messageText = errorMessage
        alert.alertStyle = NSAlertStyle.warning
        
        _ = alert.runModal()
    }
    
    func httpChanged(_ notification: Notification) {
        if notification.userInfo != nil {
            let host = notification.userInfo!["host"] as! NSString
            let port = notification.userInfo!["port"] as! NSString
            
            self.syncthingBar!.settings!.port = port as String
            
            syncthingBar!.enableUIOpener("http://\(host):\(port)")
        } else {
            syncthingBar!.disableUIOpener()
        }
    }
    
    func foldersDetermined(_ notification: Notification) {
        if let folders = notification.userInfo!["folders"] as? Array<SyncthingFolder> {
            syncthingBar!.setFolders(folders)
        }
    }
    
    func settingsSet(_ notification: Notification) {
        // ctp: maybe we should have a Settings class ...
        if let settings_ntfc = notification.userInfo!["settings"] as? SyncthingSettings {
            
            var valid_port : Bool = true
            let port_ntfc : String = settings_ntfc.port
            
            if ((port_ntfc.characters.count < 3) || (port_ntfc.characters.count > 5)) {
                valid_port = false
            }
            
            let portFromString = Int(port_ntfc)
            if ((portFromString) != nil) {
                if ((portFromString < 1000) || (portFromString > 65535)) {
                    valid_port = false
                }
            }
            else {
                valid_port = false
            }
            
            if (!valid_port) {
                self.genericError("You entered an invalid port number.")
                return
            }
            
            self.syncthingBar!.updateSettings(settings_ntfc)
            
        }
        
        //start stop app monitor from here ..?
        self.monitor!.set_apps(self.syncthingBar!.settings?.monitor_apps)
        
        if self.syncthingBar!.settings!.monitoring {
            self.monitor?.startMonitor()
        } else {
            self.monitor?.stopMonitor()
        }
        
        if self.syncthingBar!.settings!.pause_on_battery {
            self.batteryMonitor?.startMonitor()
        } else {
            self.batteryMonitor?.stopMonitor()
        }
    }
    
    func startStop(_ notification: Notification) {
        // ctp: pausing execution made possible :D
        
        if let pause_ntfc = notification.userInfo!["pause"] as? Bool {
            if pause_ntfc {
                self.runner?.pause()
            }
            else {
                self.runner?.play()
            }
        }
    }
    
    func quit() {
        NSApplication.shared().terminate(self)
    }

}
