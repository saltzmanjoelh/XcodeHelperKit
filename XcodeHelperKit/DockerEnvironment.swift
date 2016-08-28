//
//  LinuxBridge.swift
//  LinuxBridge
//
//  Created by Joel Saltzman on 7/25/16.
//
//

//Execute main function, EnvironmentParser will parse and return args, main funccreate XcodeHelper and execute action

//this is meant to be triggered by Xcode. The errors output from building on Linux get displayed in Xcode
//the goal would be, clone the repo, swift build it, copy the binary into the new project
//or add a dependency to this, swift build new project, use the built binary in this source root in PreBuild phase in xcode

import Foundation


public enum DockerKey: String {
    case projectName = "PROJECT"
    case projectDirectory = "PROJECT_DIR"
    case commandOptions = "DOCKER_COMMAND_OPTIONS"
    case imageName = "DOCKER_IMAGE_NAME"
    case containerName = "DOCKER_CONTAINER_NAME"
}

public enum DockerEnvironmentError: Error, CustomStringConvertible {
    case missingEnvironmentVariable(key:DockerKey)
    public var description : String {
        get {
            switch (self) {
            case let .missingEnvironmentVariable(key):
                let string = key.rawValue
                return "You must provide a \"\(string)\" key"
            }
        }
    }
}

public struct DockerEnvironment {
    let processEnvironment = ProcessInfo.processInfo.environment
    
    
//    var environment: [DockerKey:String] {
//        get {
//            return ProcessInfo.processInfo.environment.reduce([DockerKey:String]()){ env, pair in
//                if let dockerKey = DockerKey(rawValue: pair.key) {
//                    var copy = env
//                    copy[dockerKey] = pair.value
//                    return copy
//                }
//                return env
//            }
//        }
//    }
    
    
    subscript(key:DockerKey) -> String? {
        get {
            return processEnvironment[key.rawValue]
        }
    }
    
    func projectName() throws -> String? {
        guard let value = self[.projectName] else {
            throw DockerEnvironmentError.missingEnvironmentVariable(key:.projectName)
        }
        return value
    }
    func projectDirectory() throws -> String? {
        guard let value = self[.projectDirectory] else {
            throw DockerEnvironmentError.missingEnvironmentVariable(key:.projectDirectory)
        }
        return value
    }
    func imageName() throws -> String {
        guard let value = self[.imageName] else {
            throw DockerEnvironmentError.missingEnvironmentVariable(key:.imageName)
        }
        return value
    }
//    func defaultCommandOptions() throws -> [String] {
//        return ["-v", "\(try projectDirectory()):\(try projectDirectory())", "--name", try containerName()]
//    }
//    func commandOptions() throws -> [String] {
//        if let commandOptions = try parse(key:.commandOptions) {
//            return commandOptions.components(separatedBy: " ")
//        }
//        return try defaultCommandOptions()
//    }
//    func containerName() throws -> String {
//        do {
//            return try parse(key:.containerName)
//        } catch _ {
//        }
//
//        return try parse(key:.projectName)
//    }
    
    
}
