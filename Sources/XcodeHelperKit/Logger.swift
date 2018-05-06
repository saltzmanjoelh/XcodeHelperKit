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
    public enum level: Int {
        case log
        case error
        case none
    }
    static var timers = [UUID: Timer]()
    
    public var logLevel: Logger.level
    public init(level: Logger.level = .log){
        self.logLevel = level
    }
    @discardableResult
    public func error(_ message: String, for command: Command?, logsDirectory: URL? = nil) -> UUID? {
        return log(level: .error, message: message, for: command, logsDirectory: logsDirectory)
    }
    @discardableResult
    public func log(_ handle: FileHandle, for command: Command  ) -> UUID? {
        guard let str = String.init(data: handle.availableData as Data, encoding: .utf8) else { return nil }
        return log(str, for: command)
    }
    @discardableResult
    public func log(_ message: String, for command: Command? = nil, logsDirectory: URL? = nil) -> UUID? {
        return log(level: .log, message: message, for: command, logsDirectory: logsDirectory)
    }
    public func log(level: Logger.level, message: String, for command: Command?, logsDirectory: URL? = nil) -> UUID? {
        let uuid = UUID()
        if level.rawValue < self.logLevel.rawValue {
            return uuid
        }
        if let theCommand = command {
            print("\(theCommand.title): \(message)")
        }else{
            print("\(message)")
        }
        UserDefaults.standard.addSuite(named: "com.joelsaltzman.XcodeHelper")
        if !UserDefaults.standard.bool(forKey: Logger.UserDefaultsKey) {
            return nil
        }
        let notification = NSUserNotification()
        notification.informativeText = message
//        notification.soundName = NSUserNotificationDefaultSoundName
        notification.actionButtonTitle = "Silence"
        if let directory = logsDirectory {
            notification.identifier = directory.appendingPathComponent(uuid.uuidString).path
        }else{
            notification.identifier = uuid.uuidString
        }
        
        if let theCommand = command {
            notification.title = theCommand.title
        }else{
            notification.title = "Xcode Helper"
        }
        
        
        NSUserNotificationCenter.default.deliver(notification)
            //auto dismiss when it's a completion message
            if #available(OSX 10.12, *) {
                DispatchQueue.main.async {
                    let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(5.0), repeats: false, block: { _ in
                        NSUserNotificationCenter.default.removeDeliveredNotification(notification)
                        Logger.timers.removeValue(forKey: uuid)
                    })
                    Logger.timers[uuid] = timer
                }
            }
        return uuid
    }
    
}
