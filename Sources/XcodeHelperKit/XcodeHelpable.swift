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
import xcproj

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
public struct Command {
    public var title: String
    public var description: String
    public var cliName: String
    public var envName: String
    public init(title: String, description: String, cliName: String, envName: String) {
        self.title = title
        self.description = description
        self.cliName = cliName
        self.envName = envName
    }
    public static var updateMacOSPackages = Command.init(title: "Update Packages - macOS",
                                                         description: "Update the package dependencies via 'swift package update'. Optionally, symlink your dependencies and regenerate your xcode project to prevent future updates from requiring a new xcode project to be built",
                                                         cliName: "update-macos-packages",
                                                         envName: "UPDATE_MACOS_PACKAGES")
    public static var updateDockerPackages = Command.init(title: "Update Packages - Docker",
                                                          description: "Update the packages for your Docker container in the persistent volume directory",
                                                          cliName: "update-docker-packages",
                                                          envName: "UPDATE_DOCKER_PACKAGES")
    public static var dockerBuild = Command.init(title: "Build in Docker",
                                                 description: "Build a Swift package on another platform like Linux and have the build errors appear in Xcode.",
                                                 cliName: "docker-build",
                                                 envName: "DOCKER_BUILD")
    public static var dockerBuildPhase = Command.init(title: "Add Build in Docker Phase",
                                                      description: "Update the xcodeproj to contain a 'Run Script Phase' which will call the `Build in Docker` action.",
                                                      cliName: "docker-build-phase",
                                                      envName: "DOCKER_BUILD_PHASE")
    public static var symlinkDependencies = Command.init(title: "Symlink Dependencies",
                                                         description: "Create symbolic links for the dependency packages after `swift package update` so you don't have to generate a new xcode project.",
                                                         cliName: "symlink-dependencies",
                                                         envName: "SYMLINK_DEPENDENCIES")
    public static var createArchive = Command.init(title: "Create Archive",
                                                   description: "Archive files with tar.",
                                                   cliName: "create-archive",
                                                   envName: "CREATE_ARCHIVE")
    public static var uploadArchive = Command.init(title: "Upload Archive",
                                                   description: "Upload an archive to S3",
                                                   cliName: "upload-archive",
                                                   envName: "UPLOAD_ARCHIVE")
    public static var gitTag = Command.init(title: "Git Tag",
                                            description: "Update your package's git repo's semantic versioned tag",
                                            cliName: "git-tag",
                                            envName: "GIT_TAG")
    public static var createXcarchive = Command.init(title: "Create XCArchive",
                                                     description: "Store your built binary in an xcarchive where Xcode's Organizer can keep track",
                                                     cliName: "create-xcarchive",
                                                     envName: "CREATE_XCARCHIVE")
    
    
    public static var allCommands: [Command] = [.updateMacOSPackages, updateDockerPackages, .dockerBuild,
                                                /*.clean,*/ .symlinkDependencies, .createArchive,
                                                            .createXcarchive, .uploadArchive, .gitTag]
}
public protocol XcodeHelpable {
    
    @discardableResult
    func updateDockerPackages(at sourcePath: String, inImage dockerImageName: String, withVolume persistentVolumeName: String, shouldLog: Bool) throws -> ProcessResult
    @discardableResult
    func updateMacOsPackages(at sourcePath: String, shouldLog: Bool) throws -> ProcessResult
    @available(OSX 10.11, *)
    func recursivePackagePaths(at sourcePath: String) -> [String]
    @discardableResult
    func generateXcodeProject(at sourcePath: String, shouldLog: Bool) throws -> ProcessResult
    @discardableResult
    func dockerBuild(_ sourcePath: String, with runOptions: [DockerRunOption]?, using configuration: BuildConfiguration, in dockerImageName: String, persistentVolumeName: String?, shouldLog: Bool) throws -> ProcessResult
    @discardableResult
    func addDockerBuildPhase(toTarget target: String, inProject xcprojPath: String) throws -> ProcessResult
    func addBuildPhases(_ buildPhases: [String: [PBXShellScriptBuildPhase]], toProject xcprojPath: String) throws
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
