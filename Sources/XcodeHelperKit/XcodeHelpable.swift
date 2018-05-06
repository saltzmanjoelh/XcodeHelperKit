//
//  XcodeHelpable.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 11/26/16.
//
//

import Foundation
import DockerProcess
import ProcessRunner


public enum BuildConfiguration {
    case debug
    case release
    
    public func buildDirectory(inSourcePath sourcePath:String) -> String {
        return sourcePath.hasSuffix("/") ? "\(sourcePath).build/" : "\(sourcePath)/.build/"
    }
    public func yamlPath(inSourcePath sourcePath:String) -> String {
        return buildDirectory(inSourcePath: sourcePath).appending("\(self).yaml")
    }
    public var stringValue: String {
        get {
            switch self {
            case .debug:
                return "debug"
            default:
                return "release"
            }
        }
    }
    
    public static var allValues : [BuildConfiguration] {
        get {
            return [debug, release]
        }
    }
    public init(from string:String) {
        if string == "release" {
            self = .release
        }else{
            self = .debug
        }
    }
}

public enum GitTagComponent: Int, CustomStringConvertible {
    
    case major, minor, patch
    
    public init?(stringValue: String) {
        switch stringValue {
        case "major":
            self = .major
        case "minor":
            self = .minor
        case "patch":
            self = .patch
        default:
            return nil
        }
    }
    
    public var description: String {
        switch self {
        case .major:
            return "major"
        case .minor:
            return "minor"
        case .patch:
            return "patch"
        }
    }
}
public enum Command: String {
    case updateMacOSPackages = "update-macos-packages"
    case updateDockerPackages = "update-docker-packages"
    case dockerBuild = "docker-build"
    //        case clean = "clean"
    case symlinkDependencies = "symlink-dependencies"
    case createArchive = "create-archive"
    case uploadArchive = "upload-archive"
    case gitTag = "git-tag"
    case createXcarchive = "create-xcarchive"
    public var title: String {
        switch self {
        case .updateMacOSPackages:
            return "Update Packages - macOS"
        case .updateDockerPackages:
            return "Update Packages - Docker"
        default:
            return self.rawValue.components(separatedBy: "-").map({$0.capitalized}).joined(separator: " ")
        }
    }
    public static var allCommands: [Command] = [.updateMacOSPackages, updateDockerPackages, .dockerBuild,
                                                /*.clean,*/ .symlinkDependencies, .createArchive,
                                                            .createXcarchive, .uploadArchive, .gitTag]
}
public protocol XcodeHelpable {
    
    @discardableResult
    func updateDockerPackages(at sourcePath: String, inImage dockerImageName: String, withVolume persistentVolumeName: String, shouldLog: Bool) throws -> ProcessResult
    @discardableResult
    func updateMacOsPackages(at sourcePath: String, shouldLog: Bool) throws -> ProcessResult
    @discardableResult
    func generateXcodeProject(at sourcePath: String, shouldLog: Bool) throws -> ProcessResult
    @discardableResult
    func dockerBuild(_ sourcePath: String, with runOptions: [DockerRunOption]?, using configuration: BuildConfiguration, in dockerImageName: String, persistentVolumeName: String?, shouldLog: Bool) throws -> ProcessResult
//    @discardableResult
//    func clean(sourcePath: String, shouldLog: Bool) throws -> ProcessResult
    func symlinkDependencies(at sourcePath: String, shouldLog: Bool) throws
    @discardableResult
    func createArchive(at archivePath: String, with filePaths: [String], flatList: Bool, shouldLog: Bool) throws -> ProcessResult
    func uploadArchive(at archivePath: String, to s3Bucket: String, in region: String, key: String, secret: String, shouldLog: Bool) throws
    func uploadArchive(at archivePath: String, to s3Bucket: String, in region: String, using credentialsPath: String, shouldLog: Bool) throws
    func getGitTag(at sourcePath:String, shouldLog: Bool) throws -> String
    @discardableResult
    func incrementGitTag(component: GitTagComponent, at sourcePath: String, shouldLog: Bool) throws -> String
    func gitTag(_ tag: String, repo sourcePath: String, shouldLog: Bool) throws -> ProcessResult
    func pushGitTag(tag: String, at sourcePath: String, shouldLog: Bool) throws
    @discardableResult
    func createXcarchive(in dirPath: String, with binaryPath: String, from schemeName: String, shouldLog: Bool) throws -> ProcessResult
}
