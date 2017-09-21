//
//  Logger.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 6/3/17.
//
//

import Foundation

public struct Logger {
    public static let UserDefaultsKey = "XcodeHelperKit.Logging"
    static var timers = [UUID: Timer]()
    public init(){
        
    }
    public func log(_ message: String, for command: Command?) {
        if let theCommand = command {
            print("\(theCommand.title): \(message)")
        }else{
            print("\(message)")
        }
        if !UserDefaults.standard.bool(forKey: Logger.UserDefaultsKey) {
            return
        }
        let notification = NSUserNotification()
        notification.informativeText = message
//        notification.soundName = NSUserNotificationDefaultSoundName
        notification.actionButtonTitle = "Silence"
        
        if let theCommand = command {
            notification.identifier = theCommand.title
            notification.title = theCommand.title
        }else{
            notification.identifier = "XcodeHelperKit"
            notification.title = "Xcode Helper"
        }
        
        NSUserNotificationCenter.default.deliver(notification)
//        if message == "Done" || message.contains("Error") {
            //auto dismiss when it's a completion message
            if #available(OSX 10.12, *) {
                DispatchQueue.main.async {
                    let uuid = UUID()
                    let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(3.0), repeats: false, block: { _ in
                        NSUserNotificationCenter.default.removeDeliveredNotification(notification)
                        Logger.timers.removeValue(forKey: uuid)
                    })
                    Logger.timers[uuid] = timer
                }
            }
//        }
    }
    public func log(_ handle: FileHandle, for command: Command  ) -> String {
        guard let str = String.init(data: handle.availableData as Data, encoding: .utf8) else { return "" }
        log(str, for: command)
        return str
    }
}
