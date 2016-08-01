//xcode -> swift package fetch
//PreBuild -> Packages/LinuxRunners*/ 

import Foundation
import TaskExtension
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

enum LinuxRunnerError : ErrorProtocol {
    case CleanError(message:String)
    case BuildError(message:String)
    case UpdateSymLinksError(message:String)
}

struct LinuxRunner {
    
    func bash(command:String) throws -> [String] {
        return ["/bin/bash", "-c", command]
    }
    func build(source sourcePath:String, usingConfiguration configuration:BuildConfiguration, inDockerImage imageName:String = "saltzmanjoelh/swiftubuntu") throws {
        //check if we need to clean first
        if try shouldClean(sourcePath:sourcePath, forConfiguration:configuration) {
            try clean(sourcePath: sourcePath)
        }
        let result = DockerTask(command: "run", commandOptions: ["-v", "\(sourcePath):\(sourcePath)", "--workdir", sourcePath], imageName: imageName, commandArgs: ["/usr/bin/swift", "build"]).launch()
        if let error = result.error, result.exitCode != 0 {
            throw LinuxRunnerError.BuildError(message: "Error building in Linux (\(result.exitCode)):\n\(error)")
        }
    }
    
    func shouldClean(sourcePath:String, forConfiguration configuration:BuildConfiguration) throws -> Bool {
        let yamlPath = configuration.yamlPath(inSourcePath:sourcePath)
        if FileManager.default.isReadableFile(atPath: yamlPath) {
            let yamlFile = try String(contentsOfFile: yamlPath)
            return !yamlFile.contains("\"-target\",\"x86_64-apple")//if we have a file and it contains apple target, don't clean
        }
        
        //otherwise, clean if there is a build path but the file isn't readable
        return FileManager.default.fileExists(atPath: configuration.buildDirectory(inSourcePath: sourcePath))
    }
    
    func clean(sourcePath:String) throws {
        //We can use Task instead of firing up Docker because the end result is the same. A clean .build dir
        let result = Task.run(launchPath: "/usr/bin/swift", arguments: ["build", "--clean"])
        if result.exitCode != 0, let error = result.error {
            throw LinuxRunnerError.CleanError(message: "Error cleaning: \(error)")
        }
    }
    
    func updateSymLinks(sourcePath:String) throws {
        
        //iterate Packages dir and create symlinks without the -Ver.sion.#
        let path = sourcePath.hasSuffix("/") ? sourcePath.appending("Packages/") : sourcePath.appending("/Packages/")
        guard FileManager.default.fileExists(atPath: path) else {
            throw LinuxRunnerError.UpdateSymLinksError(message: "Failed to find directory: \(path)")
        }
        for directory in try FileManager.default.contentsOfDirectory(atPath: path) {
            let versionedPackageName = "\(directory)"
            if versionedPackageName.hasPrefix(".") || versionedPackageName.range(of: "-")?.lowerBound == nil {
                continue//if it begins with . or doesn't have the - in it like LinuxRunner-1.0.0, skip it
            }
            //remove the - version number from name and create sym link
            let packageName = versionedPackageName.substring(to: versionedPackageName.range(of: "-")!.lowerBound)
            Task.run(launchPath: "/bin/ln", arguments: ["-s", path.appending(versionedPackageName), path.appending(packageName)])
        }
    }
    
}
