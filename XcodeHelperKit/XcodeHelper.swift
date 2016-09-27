//xcode -> swift package fetch
//PreBuild -> Packages/XcodeHelpers*/ 

import Foundation
import SynchronousProcess
import DockerProcess
import S3Kit

public enum BuildConfiguration {
    case debug
    case release
    
    public func buildDirectory(inSourcePath sourcePath:String) -> String {
        return sourcePath.hasSuffix("/") ? "\(sourcePath).build/" : "\(sourcePath)/.build/"
    }
    public func yamlPath(inSourcePath sourcePath:String) -> String {
        return buildDirectory(inSourcePath: sourcePath).appending("\(self).yaml")
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

public enum XcodeHelperError : Error {
    case clean(message:String)
    case fetch(message:String)
    case build(message:String)
    case updateSymLinks(message:String)
    case createArchive(message:String)
    case uploadArchive(message:String)
    case unknownOption(message:String)
}

public enum DockerEnvironmentVariable: String {
    case projectName = "PROJECT"
    case projectDirectory = "PROJECT_DIR"
    case commandOptions = "DOCKER_COMMAND_OPTIONS"
    case imageName = "DOCKER_IMAGE_NAME"
    case containerName = "DOCKER_CONTAINER_NAME"
}

public struct XcodeHelper {
    
    public init(){}
    
    @discardableResult
    public func fetchPackages(at sourcePath:String, forLinux:Bool = false, inDockerImage imageName:String? = "saltzmanjoelh/swiftubuntu") throws -> ProcessResult {
        if forLinux {
            let commandArgs = ["/bin/bash", "-c", "cd \(sourcePath) && swift package fetch"]
            let result = DockerToolboxProcess(command: "run", commandOptions: ["-v", "\(sourcePath):\(sourcePath)"], imageName: imageName, commandArgs: commandArgs).launch(silenceOutput: false)
            if let error = result.error, result.exitCode != 0 {
                throw XcodeHelperError.fetch(message: "Error building in Linux (\(result.exitCode)):\n\(error)")
            }
            return result
        }else{
            let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && swift package fetch"])
            if let error = result.error, result.exitCode != 0 {
                throw XcodeHelperError.fetch(message: "Error building in Linux (\(result.exitCode)):\n\(error)")
            }
            return result
        }
    }
    
    @discardableResult
    public func build(source sourcePath:String, usingConfiguration configuration:BuildConfiguration, inDockerImage imageName:String = "saltzmanjoelh/swiftubuntu") throws -> ProcessResult {
        //check if we need to clean first
        if try shouldClean(sourcePath:sourcePath, forConfiguration:configuration) {
            try clean(source: sourcePath)
        }
        //At the moment, building directly from a mounted volume gives errors like "error: Could not create file ... /.Package.toml"
        //rsync the files to the root of the disk (excluding .build dir) the replace the build
//        let buildDir = configuration.buildDirectory(inSourcePath: sourcePath)
//        let commandArgs = ["/bin/bash", "-c", "rsync -ar --exclude=\(buildDir) --exclude=*.git \(sourcePath) /source && cd /source && swift build && rsync -ar /source/ \(sourcePath)"]
        //simple build doesn't work
        let commandArgs = ["/bin/bash", "-c", "cd \(sourcePath) && swift build"]
        let result = DockerToolboxProcess(command: "run", commandOptions: ["-v", "\(sourcePath):\(sourcePath)"], imageName: imageName, commandArgs: commandArgs).launch(silenceOutput: false)
        if let error = result.error, result.exitCode != 0 {
            throw XcodeHelperError.build(message: "Error building in Linux (\(result.exitCode)):\n\(error)")
        }
        return result
    }
    
    public func shouldClean(sourcePath:String, forConfiguration configuration:BuildConfiguration) throws -> Bool {
        let yamlPath = configuration.yamlPath(inSourcePath:sourcePath)
        if FileManager.default.isReadableFile(atPath: yamlPath) {
            let yamlFile = try String(contentsOfFile: yamlPath)
            return yamlFile.contains("\"-target\",\"x86_64-apple")//if we have a file and it contains apple target, clean
        }
        
        //otherwise, clean if there is a build path but the file isn't readable
        return FileManager.default.fileExists(atPath: configuration.buildDirectory(inSourcePath: sourcePath))
    }
    @discardableResult
    public func clean(source:String) throws -> ProcessResult {
        //We can use Process instead of firing up Docker because the end result is the same. A clean .build dir
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(source) && /usr/bin/swift build --clean"])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.clean(message: "Error cleaning: \(error)")
        }
        return result
    }
    
    //useful for your project so that you don't have to keep updating paths for your dependencies when they change
    @discardableResult
    public func updateSymLinks(sourcePath:String) throws {
        
        //iterate Packages dir and create symlinks without the -Ver.sion.#
        let path = sourcePath.hasSuffix("/") ? sourcePath.appending("Packages/") : sourcePath.appending("/Packages/")
        guard FileManager.default.fileExists(atPath: path) else {
            throw XcodeHelperError.updateSymLinks(message: "Failed to find directory: \(path)")
        }
        for directory in try FileManager.default.contentsOfDirectory(atPath: path) {
            let versionedPackageName = "\(directory)"
            if versionedPackageName.hasPrefix(".") || versionedPackageName.range(of: "-")?.lowerBound == nil {
                continue//if it begins with . or doesn't have the - in it like XcodeHelper-1.0.0, skip it
            }
            //remove the - version number from name and create sym link
            let packageName = versionedPackageName.substring(to: versionedPackageName.range(of: "-")!.lowerBound)
            let result = Process.run("/bin/ln", arguments: ["-s", path.appending(versionedPackageName), path.appending(packageName)])
            if result.exitCode != 0, let error = result.error {
                throw XcodeHelperError.clean(message: "Error cleaning: \(error)")
            }
        }
    }
    @discardableResult
    public func createArchive(at archivePath:String, with filePaths:[String], flatList:Bool = true) throws -> ProcessResult {
        let args = flatList ? filePaths.flatMap{ return ["-C", URL(fileURLWithPath:$0).deletingLastPathComponent().path, URL(fileURLWithPath:$0).lastPathComponent] } : filePaths
        let arguments = ["-cvzf", archivePath]+args
        let result = Process.run("/usr/bin/tar", arguments: arguments)
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.createArchive(message: "Error creating archive: \(error)")
        }
        return result
    }
    
    
    @discardableResult
    public func uploadArchive(at archivePath:String, to s3Bucket:String, in region: String, key: String, secret: String) throws  {
        let result = try S3.with(key: key, and: secret).upload(file: URL.init(fileURLWithPath: archivePath), to: s3Bucket, in: region)
        if result.response.statusCode != 200 {
            var description = result.response.description
            if let data = result.data as? Data {
                if let text = NSString(data:data, encoding:String.Encoding.utf8.rawValue) as? String {
                    description += "\n\(text)"
                }
            }
            throw XcodeHelperError.uploadArchive(message: description)
        }
        
    }
    @discardableResult
    public func uploadArchive(at archivePath:String, to s3Bucket:String, in region: String, using credentialsPath: String) throws  {
        let result = try S3.with(credentials: credentialsPath).upload(file: URL.init(fileURLWithPath: archivePath), to: s3Bucket, in: region)
        if result.response.statusCode != 200 {
            var description = result.response.description
            if let data = result.data as? Data {
                if let text = NSString(data:data, encoding:String.Encoding.utf8.rawValue) as? String {
                    description += "\n\(text)"
                }
            }
            throw XcodeHelperError.uploadArchive(message: description)
        }
        
    }
}

