//
//  XcodeHelpable.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 11/26/16.
//
//

import Foundation
import SynchronousProcess
import DockerProcess


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

public enum GitTagComponent: Int {
    
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
    
}

public protocol XcodeHelpable {
    

    @discardableResult func updatePackages(at sourcePath: String, using dockerImageName: String?) throws -> ProcessResult
    @discardableResult func generateXcodeProject(at sourcePath: String) throws -> ProcessResult
    @discardableResult func dockerBuild(_ sourcePath: String, with runOptions: [DockerRunOption]?, using configuration: BuildConfiguration, in dockerImageName: String, persistentBuildDirectory: String?) throws -> ProcessResult
    @discardableResult func clean(sourcePath: String) throws -> ProcessResult
    @discardableResult func symlinkDependencies(at sourcePath: String) throws
    @discardableResult func createArchive(at archivePath: String, with filePaths: [String], flatList: Bool) throws -> ProcessResult
    @discardableResult func uploadArchive(at archivePath: String, to s3Bucket: String, in region: String, key: String, secret: String) throws
    @discardableResult func uploadArchive(at archivePath: String, to s3Bucket: String, in region: String, using credentialsPath: String) throws
    @discardableResult func incrementGitTag(component: GitTagComponent, at sourcePath: String) throws -> String
    func gitTag(_ tag: String, repo sourcePath: String) throws
    func pushGitTag(tag: String, at sourcePath: String) throws
    @discardableResult func createXcarchive(in dirPath: String, with binaryPath: String, from schemeName: String) throws -> String
}
