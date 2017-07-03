//
//  Logger.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 6/3/17.
//
//

import Foundation

public struct Logger {
    
    public func log(_ message: String, for action: Action) {
        let notification = NSUserNotification()
        notification.identifier = action.rawValue
        notification.title = action.rawValue
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.actionButtonTitle = "Silence"
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    public func log(_ handle: FileHandle, for action: Action) -> String {
        guard let str = String.init(data: handle.availableData as Data, encoding: .utf8) else { return "" }
        log(str, for: action)
        return str
    }
}
