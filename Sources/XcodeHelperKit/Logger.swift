//
//  Logger.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 6/3/17.
//
//

import Foundation
import ProcessRunner
import os.log

public struct Logger {
    public struct LogIdentifier {
        public let category: String
        public let pid: Int32
    }
    public struct LogEntry {
        public let uuid: UUID
        public let timer: Timer
        public let notification: NSUserNotification
        public let identifier: LogIdentifier
    }
    
    public static let subsystemIdentifier = "com.joelsaltzman.XcodeHelper"
    public static let UserDefaultsKey = "XcodeHelperKit.Logging"
    
    public static var timers = [UUID: LogEntry]()
    
    private let logSystem: OSLog?
    private let identifier: LogIdentifier
    public init(category: String){
        if #available(OSX 10.12, *) {
            logSystem = OSLog.init(subsystem: Logger.subsystemIdentifier, category: category)
        } else {
            // Fallback on earlier versions
            logSystem = nil
        }
        identifier = LogIdentifier.init(category: category, pid: ProcessInfo.processInfo.processIdentifier)
    }
    
    @discardableResult
    public func error(_ message: StaticString, _ args: CVarArg...) -> UUID? {
        if #available(OSX 10.12, *) {
            return log(type: .error, message: message, args)
        } else {
            // Fallback on earlier versions
            return log(type: OSLogType.init(16), message: message, args)
        }
    }
    @discardableResult
    public func errorWithNotification(_ message: StaticString, _ args: CVarArg...) -> UUID? {
        var uuid: UUID?
        if #available(OSX 10.12, *) {
            uuid = log(type: .default, message: message, args)
        } else {
            // Fallback on earlier versions
            uuid = log(type: OSLogType.init(16), message: message, args)
        }
        if let theUUID = uuid {
            displayNotification(uuid: theUUID, withMessage: message, args)
            removeOtherNotifications(except: theUUID)
        }
        return uuid
    }
    @discardableResult
    public func log(_ message: StaticString, _ args: CVarArg...) -> UUID? {
        if #available(OSX 10.12, *) {
            return log(type: .default, message: message, args)
        } else {
            // Fallback on earlier versions
            return log(type: OSLogType.init(0), message: message, args)
        }
    }
    @discardableResult
    public func logWithNotification(_ message: StaticString, _ args: CVarArg...) -> UUID? {
        var uuid: UUID?
        if #available(OSX 10.12, *) {
            uuid = log(type: .default, message: message, args)
        } else {
            // Fallback on earlier versions
            uuid = log(type: OSLogType.init(0), message: message, args)
        }
        if let theUUID = uuid {
            displayNotification(uuid: theUUID, withMessage: message, args)
        }
        return uuid
    }
//    public func log(type: OSLogType, message: StaticString, args: CVarArg...) -> UUID? {
//        let uuid = UUID()
//        if #available(OSX 10.12, *) {
//            if let system = logSystem {
//                os_log(message, log: system, type: type, args)
////                os_log(message, log: system, type: type, args)
//            }else{
//                print(message)
//            }
//        }else{
//            print(message)
//        }
//
//        return uuid
//    }
    private func log(type: OSLogType, message: StaticString, _ args: [CVarArg]) -> UUID? {
        let uuid = UUID()
        if #available(OSX 10.12, *) {
            if let system = logSystem {
                switch args.count {
                case 0:
                    os_log(message, log: system, type: type)
                case 1:
                    os_log(message, log: system, type: type, args[0])
                case 2:
                    os_log(message, log: system, type: type, args[0], args[1])
                case 3:
                    os_log(message, log: system, type: type, args[0], args[1], args[2])
                case 4:
                    os_log(message, log: system, type: type, args[0], args[1], args[2], args[3])
                case 5:
                    os_log(message, log: system, type: type, args[0], args[1], args[2], args[3], args[4])
                default:
                    os_log(message, log: system, type: type, args)
                }
            } else {
                print(compileFormatString(message, args))
            }
        } else {
            print(compileFormatString(message, args))
        }
        return uuid
    }
    func displayNotification(uuid: UUID, withMessage message: StaticString, _ args: [CVarArg]) {
        //UserDefaults.standard.addSuite(named: "com.joelsaltzman.XcodeHelper")
        let defaults = Bundle.main.bundleIdentifier == "com.joelsaltzman.XcodeHelper" ? UserDefaults.standard : UserDefaults.init(suiteName: "com.joelsaltzman.XcodeHelper")
        if defaults?.bool(forKey: Logger.UserDefaultsKey) == false {
            return
        }
        let notification = NSUserNotification()
        
        notification.identifier = uuid.uuidString
        notification.title = identifier.category
        notification.informativeText = compileFormatString(message, args)
        //        notification.soundName = NSUserNotificationDefaultSoundName
        notification.actionButtonTitle = "Silence"
        
        
        NSUserNotificationCenter.default.deliver(notification)
        //auto dismiss when it's a completion message
        if #available(OSX 10.12, *) {
            let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(5.0), repeats: false, block: { _ in
                DispatchQueue.main.async {
                    NSUserNotificationCenter.default.removeDeliveredNotification(notification)
                    Logger.timers.removeValue(forKey: uuid)
                }
            })
            Logger.timers[uuid] = LogEntry.init(uuid: uuid,
                                                timer: timer,
                                                notification: notification,
                                                identifier: identifier)
            
        }
    }
    func removeOtherNotifications(except uuid: UUID) {
        let entries = Logger.timers.values.compactMap { (value: LogEntry) -> LogEntry? in
            guard value.uuid != uuid else { return nil }
            return value
        }
        for entry in entries {
            Logger.timers.removeValue(forKey: entry.uuid)
            NSUserNotificationCenter.default.removeDeliveredNotification(entry.notification)
        }
    }
    func compileFormatString(_ message: StaticString, _ args: [CVarArg]) -> String {
        switch args.count {
        case 0:
            return String.init(format: message.description)
        case 1:
            return String.init(format: message.description, args[0])
        case 2:
            return String.init(format: message.description, args[0], args[1])
        case 3:
            return String.init(format: message.description, args[0], args[1], args[2])
        case 4:
            return String.init(format: message.description, args[0], args[1], args[2], args[3])
        case 5:
            return String.init(format: message.description, args[0], args[1], args[2], args[3], args[4])
        default:
            return String.init(format: message.description, args)
        }
    }
}
