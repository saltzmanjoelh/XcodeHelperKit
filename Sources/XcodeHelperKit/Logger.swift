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
        let category: String
        let pid: Int
    }
    
    public static let subsystemIdentifier = "com.joelsaltzman.XcodeHelper.plist"
    public static let UserDefaultsKey = "XcodeHelperKit.Logging"
    
    static var timers = [UUID: Timer]()
    //log show --style compact --predicate '(subsystem == "com.joelsaltzman.XcodeHelper.plist") && (category == "Update Packages - macOS")'
    
    private let logSystem: OSLog?
    public init(category: String){
//        let pid = ProcessInfo.processInfo.processIdentifier
//        print("pid: \(pid)")
        if #available(OSX 10.12, *) {
            logSystem = OSLog.init(subsystem: Logger.subsystemIdentifier, category: category)
        } else {
            // Fallback on earlier versions
            logSystem = nil
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
    public func log(_ message: StaticString, _ args: CVarArg...) -> UUID? {
        if #available(OSX 10.12, *) {
            return log(type: .default, message: message, args)
        } else {
            // Fallback on earlier versions
            return log(type: OSLogType.init(0), message: message, args)
        }
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
        
        notification.informativeText = compileFormatString(message, args)
        //        notification.soundName = NSUserNotificationDefaultSoundName
        notification.actionButtonTitle = "Silence"
        //        if let directory = logsDirectory {
        //            notification.identifier = directory.appendingPathComponent(uuid.uuidString).path
        //        }else{
        //            notification.identifier = uuid.uuidString
        //        }
        
        //        if let theCommand = command {
        //            notification.title = theCommand.title
        //        }else{
        //            notification.title = "Xcode Helper"
        //        }
        
        
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
    }
    func compileFormatString(_ message: StaticString, _ args: [CVarArg]) -> String {
        switch args.count {
        case 0:
            return String.init(format: message.description, args[0])
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
    public func logStringFromProcessResults(_ processResults: [ProcessResult]) -> String {
        return ""
    }
    @discardableResult
    public func storeLog(_ log: String, inDirectory directory: URL, uuid: UUID) throws -> String? {
        return nil
    }
}
