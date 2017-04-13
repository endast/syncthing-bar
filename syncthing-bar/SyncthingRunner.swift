//
//  SyncthingRunner.swift
//  syncthing-bar
//
//  Created by Andreas Streichardt on 13.12.14.
//  Copyright (c) 2014 mop. All rights reserved.
//

import Foundation

let TooManyErrorsNotification = "koeln.mop.too-many-errors"
let HttpChanged = "koeln.mop.http-changed"
let FoldersDetermined = "koeln.mop.folders-determined"
let SettingsSet = "koeln.mop.settings-set"
let StartStop = "koeln.mop.start-stop"

class SyncthingRunner: NSObject {
    var portFinder : PortFinder = PortFinder(startPort: 8084)
    var path : NSString
    //var path : NSString = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"binaryname"]"/Users/mop/Downloads/syncthing-macosx-amd64-v0.10.8/syncthing"
    var task: Process?
    var port: NSInteger?
    var lastFail : Date?
    var failCount : NSInteger = 0
    var notificationCenter: NotificationCenter = NotificationCenter.default
    var portOpenTimer : Timer?
    var repositoryCollectorTimer : Timer?
    var log : SyncthingLog
    var buf : NSString = NSString()
    var apiKey: NSString?
    var version: [Int]?
    var paused: Bool

    init(log: SyncthingLog) {
        self.paused = false
        self.log = log
        path = Bundle.main.path(forResource: "syncthing/syncthing", ofType: "")!
        
        super.init()
    
        notificationCenter.addObserver(self, selector: #selector(SyncthingRunner.taskStopped(_:)), name: Process.didTerminateNotification, object: task)
        notificationCenter.addObserver(self, selector: #selector(SyncthingRunner.receivedOut(_:)), name: NSNotification.Name.NSFileHandleDataAvailable, object: nil)
    }
    
    func registerVersion() -> Bool {
        let pipe : Pipe = Pipe()
        let versionTask = Process()
        versionTask.launchPath = path as String
        versionTask.arguments = ["--version"]
        versionTask.standardOutput = pipe
        versionTask.launch()
        versionTask.waitUntilExit()
        
        let versionOut = pipe.fileHandleForReading.readDataToEndOfFile()
        let versionString = NSString(data: versionOut, encoding: String.Encoding.utf8)
        
        let regex = try? NSRegularExpression(pattern: "^syncthing v(\\d+)\\.(\\d+)\\.(\\d+)",
            options: [])
        var results = regex!.matches(in: versionString! as String, options: [], range: NSMakeRange(0, versionString!.length))
        if results.count == 1 {
            let major = Int((versionString?.substring(with: results[0].rangeAt(1)))!) as Int!
            let minor = Int((versionString?.substring(with: results[0].rangeAt(2)))!) as Int!
            let patch = Int((versionString?.substring(with: results[0].rangeAt(3)))!) as Int!
            
            version = [ major, minor, patch ]
            print("Syncthing version \(version![0]) \(version![1]) \(version![2])")
            return true
        } else {
            return false
        }
    }
    
    func run() -> (String?) {
        let pipe : Pipe = Pipe()
        let readHandle = pipe.fileHandleForReading
        
        task = Process()
        task!.launchPath = path as String
        var environment = ProcessInfo.processInfo.environment 
        environment["STNORESTART"] =  "1"
        task!.environment = environment

        let port = self.port!
        let httpData : [String: String] = ["host": "127.0.0.1", "port": String(port)];
        
        self.apiKey = randomStringWithLength(32);
        
        task!.arguments = ["-no-browser", "-gui-address=127.0.0.1:\(port)", "-gui-apikey=\(self.apiKey!)"]
        task!.standardOutput = pipe
        readHandle.waitForDataInBackgroundAndNotify()
        task!.launch()
        
        
        // mop: wait until port is open :O
        portOpenTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(SyncthingRunner.checkPortOpen(_:)), userInfo: httpData, repeats: true)
        return nil
    }
    
    func receivedOut(_ notif : Notification) {
        // Unpack the FileHandle from the notification
        let fh:FileHandle = notif.object as! FileHandle
        // Get the data from the FileHandle
        let data = fh.availableData
        // Only deal with the data if it actually exists
        if data.count > 1 {
            // Since we just got the notification from fh, we must tell it to notify us again when it gets more data
            fh.waitForDataInBackgroundAndNotify()
            // Convert the data into a string
            let string = (buf as String) + (NSString(data: data, encoding: String.Encoding.utf8)! as String)
            var lines = string.components(separatedBy: "\n")
            buf = lines.removeLast()
            for line in lines {
                log.log("OUT: \(line)")
            }
        }
    }
    
    func ensureRunning() -> (String?) {
        if !registerVersion() {
            return "Could not determine syncthing version"
        }
        let result = portFinder.findPort()
        // mop: ITS GO :O ZOMG!!111
        if (result.err != nil) {
            return "Could not find a port!"
        }
        self.port = result.port
        let err = run()
        return err
    }
    
    // mop: copy paste :D http://stackoverflow.com/questions/26845307/generate-random-alphanumeric-string-in-swift looks good to me
    func randomStringWithLength (_ len : Int) -> NSString {
        let letters : NSString = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        
        let randomString : NSMutableString = NSMutableString(capacity: len)
        
        for _ in 1...len {
            let length = UInt32 (letters.length)
            let rand = arc4random_uniform(length)
            randomString.appendFormat("%C", letters.character(at: Int(rand)))
        }
        
        return randomString
    }
    
    func createRequest(_ path: NSString) -> NSMutableURLRequest {
        let url = URL(string: "http://localhost:\(self.port!)\(path)")
        let request = NSMutableURLRequest(url: url!)
        request.addValue(self.apiKey! as String, forHTTPHeaderField: "X-API-Key")
        return request
    }
    
    func collectRepositories(_ timer: Timer) {
        // mop: jaja copy paste...must fix somewhen
        if (timer.userInfo as? Dictionary<String,String>) != nil {
            let request: NSMutableURLRequest = createRequest("/rest/system/config")
            let idElement: NSString = "id"
            let labelElement: NSString = "label"
            let pathElement: NSString = "path"
            let foldersElement: NSString = "folders"
            
            NSURLConnection.sendAsynchronousRequest(request, queue: OperationQueue.main) {(response, data, error) in
                if (error != nil) {
                    print("Got error collecting repositories \(error)")
                    return;
                }
                let httpResponse = response as? HTTPURLResponse;
                if httpResponse == nil {
                    print("Unexpected response");
                    return;
                }
                
                if httpResponse!.statusCode != 200 {
                    print("Got non 200 HTTP Response \(httpResponse!.statusCode)");
                    return;
                }
                if (error == nil) {
                    let jsonResult: NSDictionary = (try! JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions.mutableContainers)) as! NSDictionary
                    
                    // mop: WTF am i typing :S
                    let folders = jsonResult[foldersElement] as? Array<AnyObject>
                    if folders != nil {
                        let folderStructArr = folders!.filter({(object: AnyObject) -> (Bool) in
                            let id = object[idElement] as? String
                            let path = object[pathElement] as? String
                            
                            return id != nil && path != nil
                        }).map({(object: AnyObject) -> (SyncthingFolder) in
                            let id = object[idElement] as? String
                            let pathTemp = object[pathElement] as? String
                            let path = ((pathTemp)! as NSString).expandingTildeInPath
                            let label = object[labelElement] as? String
                            
                            return SyncthingFolder(id: id!, path: path, label: label!)
                        })
                        
                        let folderData = ["folders": folderStructArr]
                        self.notificationCenter.post(name: Notification.Name(rawValue: FoldersDetermined), object: self, userInfo: folderData)
                    } else {
                        print("Failed to parse folders :(")
                    }
                } else {
                    print("Got error collecting repositories \(error)")
                }
            }
        }
    }
    
    func checkPortOpen(_ timer: Timer) {
        if (timer.isValid) {
            if let info = timer.userInfo as? Dictionary<String,String> {
                let host = info["host"]
                let port = info["port"]

                let request = createRequest("/rest/version")
                
                NSURLConnection.sendAsynchronousRequest(request, queue: OperationQueue.main) {(response, data, error) in
                    if (error == nil) {
                        let httpData = ["host": host!, "port": port!]
                        self.notificationCenter.post(name: Notification.Name(rawValue: HttpChanged), object: self, userInfo: httpData)
                        if (self.portOpenTimer!.isValid) {
                            self.portOpenTimer!.invalidate()
                        }
                        self.repositoryCollectorTimer = Timer.scheduledTimer(timeInterval: 10.0, target: self, selector: #selector(SyncthingRunner.collectRepositories(_:)), userInfo: info, repeats: true)
                        self.repositoryCollectorTimer!.fire()
                    }
                }
            }
        }
    }
    
    func taskStopped(_ sender: AnyObject) {
        let task = sender.object as! Process
        if (task != self.task) {
            return
        }
        
        self.notificationCenter.post(name: Notification.Name(rawValue: HttpChanged), object: self)
        
        if (self.paused) {
            // ctp: DO NOT attempt restart when paused ...
            return
        }
        
        stopTimers()
        
        let current = Date()
        // mop: retry 5 times :S
        if (lastFail != nil) {
            let timeDiff = current.timeIntervalSince(lastFail!)
            if (timeDiff > 5) {
                failCount = 0
            } else if (failCount <= 5) {
                failCount += 1
            } else {
                notificationCenter.post(name: Notification.Name(rawValue: TooManyErrorsNotification), object: self)
                print("Too many errors. Stopping")
                return
            }
        }
        lastFail = current
        run()
    }
    
    func stopTimers() {
        if (portOpenTimer != nil && portOpenTimer!.isValid) {
            portOpenTimer!.invalidate()
        }
        
        if (repositoryCollectorTimer != nil) {
            if (repositoryCollectorTimer!.isValid) {
                repositoryCollectorTimer!.invalidate()
            }
        }
    }
    
    func pause() {
        if (self.paused) {
            return
        }
        
        self.paused = true
        self.stop()
    }
    
    func play() {
        if (!self.paused) {
            return
        }
        
        self.paused = false
        self.run()
    }
    
    func stop() {
        if (task != nil) {
            task!.terminate();
        }
        stopTimers()
    }
}
