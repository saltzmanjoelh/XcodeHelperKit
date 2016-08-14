//xcode -> swift package fetch
//PreBuild -> Packages/XcodeHelpers*/ 

import Foundation
import SynchronousTask
import DockerTask


enum BuildConfiguration {
    case debug
    case release
    
    func buildDirectory(inSourcePath sourcePath:String) -> String {
        return sourcePath.hasSuffix("/") ? "\(sourcePath).build/" : "\(sourcePath)/.build/"
    }
    func yamlPath(inSourcePath sourcePath:String) -> String {
        return buildDirectory(inSourcePath: sourcePath).appending("\(self).yaml")
    }
    
    static var allValues : [BuildConfiguration] {
        get {
            return [debug, release]
        }
    }
}

enum XcodeHelperError : Error {
    case clean(message:String)
    case fetch(message:String)
    case build(message:String)
    case updateSymLinks(message:String)
    case createArchive(message:String)
    case uploadArchive(message:String)
}

struct XcodeHelper {
    
    @discardableResult
    func fetchPackages(at sourcePath:String, forLinux:Bool = false, inDockerImage imageName:String? = "saltzmanjoelh/swiftubuntu") throws -> DockerTaskResult {
        if forLinux {
            //TODO: updated toolbox task to wrap in strings?
            let commandArgs = ["/bin/bash", "-c", "cd \(sourcePath) && swift package fetch"]
            let result = DockerToolboxTask(command: "run", commandOptions: ["-v", "\(sourcePath):\(sourcePath)"], imageName: imageName, commandArgs: commandArgs).launch(silenceOutput: false)
            if let error = result.error, result.exitCode != 0 {
                throw XcodeHelperError.fetch(message: "Error building in Linux (\(result.exitCode)):\n\(error)")
            }
            return result
        }else{
            let result = Task.run(launchPath: "/bin/bash", arguments: ["-c", "cd \(sourcePath) && swift package fetch"])
            if let error = result.error, result.exitCode != 0 {
                throw XcodeHelperError.fetch(message: "Error building in Linux (\(result.exitCode)):\n\(error)")
            }
            return result
        }
    }
    
    @discardableResult
    func build(source sourcePath:String, usingConfiguration configuration:BuildConfiguration, inDockerImage imageName:String = "saltzmanjoelh/swiftubuntu") throws -> DockerTaskResult {
        //check if we need to clean first
        if try shouldClean(sourcePath:sourcePath, forConfiguration:configuration) {
            try clean(sourcePath: sourcePath)
        }
        //At the moment, building directly from a mounted volume gives errors like "error: Could not create file ... /.Package.toml"
        //rsync the files to the root of the disk (excluding .build dir) the replace the build
//        let buildDir = configuration.buildDirectory(inSourcePath: sourcePath)
//        let commandArgs = ["/bin/bash", "-c", "rsync -ar --exclude=\(buildDir) --exclude=*.git \(sourcePath) /source && cd /source && swift build && rsync -ar /source/ \(sourcePath)"]
        //simple build doesn't work
        let commandArgs = ["/bin/bash", "-c", "cd \(sourcePath) && swift build"]
        let result = DockerToolboxTask(command: "run", commandOptions: ["-v", "\(sourcePath):\(sourcePath)"], imageName: imageName, commandArgs: commandArgs).launch(silenceOutput: false)
        if let error = result.error, result.exitCode != 0 {
            throw XcodeHelperError.build(message: "Error building in Linux (\(result.exitCode)):\n\(error)")
        }
        return result
    }
    
    func shouldClean(sourcePath:String, forConfiguration configuration:BuildConfiguration) throws -> Bool {
        let yamlPath = configuration.yamlPath(inSourcePath:sourcePath)
        if FileManager.default.isReadableFile(atPath: yamlPath) {
            let yamlFile = try String(contentsOfFile: yamlPath)
            return yamlFile.contains("\"-target\",\"x86_64-apple")//if we have a file and it contains apple target, clean
        }
        
        //otherwise, clean if there is a build path but the file isn't readable
        return FileManager.default.fileExists(atPath: configuration.buildDirectory(inSourcePath: sourcePath))
    }
    @discardableResult
    func clean(sourcePath:String) throws -> DockerTaskResult {
        //We can use Task instead of firing up Docker because the end result is the same. A clean .build dir
        let result = Task.run(launchPath: "/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/swift build --clean"])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.clean(message: "Error cleaning: \(error)")
        }
        return result
    }
    
    //useful for your project so that you don't have to keep updating paths for your dependencies when they change
    @discardableResult
    func updateSymLinks(sourcePath:String) throws {
        
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
            let result = Task.run(launchPath: "/bin/ln", arguments: ["-s", path.appending(versionedPackageName), path.appending(packageName)])
            if result.exitCode != 0, let error = result.error {
                throw XcodeHelperError.clean(message: "Error cleaning: \(error)")
            }
        }
    }
    @discardableResult
    func create(archive archivePath:String, files filePaths:[String], flatList:Bool) throws -> DockerTaskResult {
        let args = flatList ? filePaths.flatMap{ return ["-C", URL(fileURLWithPath:$0).deletingLastPathComponent().path, URL(fileURLWithPath:$0).lastPathComponent] } : filePaths
        let arguments = ["-cvzf", archivePath]+args
        let result = Task.run(launchPath: "/usr/bin/tar", arguments: arguments)
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.createArchive(message: "Error creating archive: \(error)")
        }
        return result
    }
    
    //Currently requires aws cli tool, use like cp {source} s3://{destination}
    //TODO: use REST API
    @discardableResult
    func upload(archive archivePath:String, to s3Path:String, using awsCliPath:String = "/usr/local/bin/aws") throws -> DockerTaskResult {
        let result = Task.run(launchPath: awsCliPath, arguments: ["s3", "cp", archivePath, s3Path])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.uploadArchive(message: "Error uploading archive: \(error)")
        }
        return result
    }
    
//    func commit(to branch:String, tag)
}
