//
//  SyncthingBar.swift
//  syncthing-bar
//
//  Created by Andreas Streichardt on 14.12.14.
//  Copyright (c) 2014 mop. All rights reserved.
//

import Cocoa

let FolderTag = 1

open class SyncthingBar: NSObject {
    var statusBar: NSStatusBar = NSStatusBar.system()
    var statusBarItem : NSStatusItem = NSStatusItem()
    var menu : NSMenu = NSMenu()
    var openUIItem: NSMenuItem
    var startStopSyncthingItem: NSMenuItem
    var url: NSString?
    var controller: LogWindowController?
    var settings: SyncthingSettings?
    var setter: SettingsWindowController?
    var log : SyncthingLog
    open var workspace : NSWorkspace = NSWorkspace.shared()
    
    public init(log : SyncthingLog) {
        self.log = log
        //Add statusBarItem
        statusBarItem = statusBar.statusItem(withLength: -1)
        statusBarItem.menu = menu
        
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(named: "syncthing-bar")
        // mop: that is the preferred way but the image is currently not drawn as it has to be and i am not an artist :(
        icon?.isTemplate = true
        icon?.size = size
        statusBarItem.image = icon
        
        menu.autoenablesItems = false
        
        openUIItem = NSMenuItem()
        openUIItem.title = "Open UI"
        openUIItem.action = #selector(SyncthingBar.openUIAction(_:))
        openUIItem.isEnabled = false
        menu.addItem(openUIItem)
        
        startStopSyncthingItem = NSMenuItem()
        startStopSyncthingItem.title = "Stop Syncthing"
        startStopSyncthingItem.action = #selector(SyncthingBar.startStopSyncthingAction(_:))
        startStopSyncthingItem.isEnabled = false
        menu.addItem(startStopSyncthingItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let openLogItem : NSMenuItem = NSMenuItem()
        openLogItem.title = "Show Log"
        openLogItem.action = #selector(SyncthingBar.openLogAction(_:))
        openLogItem.isEnabled = true
        menu.addItem(openLogItem)
        
        // this will automagically check, if there are already settings stored and load them ...
        settings = SyncthingSettings()
        
        let openSettingsItem : NSMenuItem = NSMenuItem()
        openSettingsItem.title = "Settings"
        openSettingsItem.action = #selector(SyncthingBar.openSettingsAction(_:))
        openSettingsItem.isEnabled = true
        menu.addItem(openSettingsItem)
        
        let quitItem : NSMenuItem = NSMenuItem()
        quitItem.title = "Quit"
        quitItem.action = Selector("quitAction:")
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        
        super.init()
        // mop: todo: move the remaining actions as well
        openUIItem.target = self
        startStopSyncthingItem.target = self
        openLogItem.target = self
        openSettingsItem.target = self
        
        self.updateSettings(self.settings!)
    }
    
    func enableUIOpener(_ uiUrl: NSString) {
        url = uiUrl
        openUIItem.isEnabled = true
        startStopSyncthingItem.isEnabled = true
    }
    
    func disableUIOpener() {
        openUIItem.isEnabled = false
    }
    
    func setFolders(_ folders: Array<SyncthingFolder>) {
        // mop: should probably check if anything changed ... but first simple stupid :S
        var item = menu.item(withTag: FolderTag)
        while (item != nil) {
            menu.removeItem(item!)
            item = menu.item(withTag: FolderTag)
        }
        
        // mop: maybe findByTag instead of hardcoded number?
        let startInsertIndex = 3
        var folderCount = 0
        for folder in folders {
            let folderItem : NSMenuItem = NSMenuItem()
            folderItem.title = "Open \(folder.label.length > 0 ? folder.label : folder.id) in Finder"
            folderItem.representedObject = folder
            folderItem.action = #selector(SyncthingBar.openFolderAction(_:))
            folderItem.isEnabled = true
            folderItem.tag = FolderTag
            folderItem.target = self
            menu.insertItem(folderItem, at: startInsertIndex + folderCount)
            folderCount = folderCount + 1
        }
        
        // mop: only add if there were folders (we already have a separator after "Open UI")
        if (folderCount > 0) {
            let lowerSeparator = NSMenuItem.separator()
            // mop: well a bit hacky but we need to clear this one as well ;)
            lowerSeparator.tag = FolderTag
            menu.insertItem(lowerSeparator, at: startInsertIndex + folderCount)
        }
    }
    
    func openUIAction(_ sender: AnyObject) {
        if (url != nil) {
            workspace.open(URL(string: url! as String)!)
        }
    }
    
    func startStopSyncthingAction(_ sender: AnyObject) {
        let notificationCenter: NotificationCenter = NotificationCenter.default
        let title: String = (sender as! NSMenuItem).title
        if title.range(of: "Stop") != nil {
            (sender as! NSMenuItem).title = "Start Syncthing"
            let startStopData = ["pause": true]
            notificationCenter.post(name: Notification.Name(rawValue: StartStop), object: self, userInfo: startStopData)
        }
        else {
            (sender as! NSMenuItem).title = "Stop Syncthing"
            let startStopData = ["pause": false]
            notificationCenter.post(name: Notification.Name(rawValue: StartStop), object: self, userInfo: startStopData)
        }
    }
    
    open func openFolderAction(_ sender: AnyObject) {
        let folder = (sender as! NSMenuItem).representedObject as! SyncthingFolder
        workspace.open(URL(fileURLWithPath: folder.path as String))
    }
    
    func openLogAction(_ sender: AnyObject) {
        // mop: recreate even if it exists (not sure if i manually need to close and cleanup :S)
        // seems wrong to me but works (i want to view current log output :S)
        controller = LogWindowController(log: log)
        controller?.showWindow(self)
        //controller?.window?.makeMainWindow()
        controller?.window?.makeKeyAndOrderFront(self)
    }
    
    func openSettingsAction(_ sender: AnyObject) {
        // ctp: settins window only used for syncthing-bar, not syncthing itself, although we could also configure port here ...
        
        setter = SettingsWindowController(settings: self.settings!)
        setter?.showWindow(self)
        //setter?.window?.makeMainWindow()
        setter?.window?.makeKeyAndOrderFront(self)
    }
    
    func updateSettings(_ settings: SyncthingSettings) {
        // ctp: somewhat redundany to storing this in the settings controller already?
        // maybe we shouldn't create the settings window over and over ?
        
        // TODO: we are not storing these settings anywhere useful, yet
        // TODO: maybe create an app-settings-dir in the appropriate ~/Library location and write the settings into there?
        
        self.settings = settings
        
        let icon: NSImage?;
        let size = NSSize(width: 18, height: 18)
        
        if (self.settings!.bw_icon) {
            if (self.settings!.invert_icon) {
                icon = NSImage(named: "syncthing-bar-invert")
                icon?.isTemplate = true
                icon?.size = size
                statusBarItem.image = icon
            } else {
                icon = NSImage(named: "syncthing-bar")
                icon?.isTemplate = true
                icon?.size = size
                statusBarItem.image = icon
            }
        } else {
            icon = NSImage(named: "AppIcon")
            //icon?.setTemplate(true)
            icon?.size = size
            statusBarItem.image = icon
        }
        
        self.settings?.saveSettings()

    }
 
}
