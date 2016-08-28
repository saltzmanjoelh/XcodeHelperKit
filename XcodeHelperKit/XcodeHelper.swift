//xcode -> swift package fetch
//PreBuild -> Packages/XcodeHelpers*/ 

import Foundation
import SynchronousProcess
import DockerProcess
import CLIRunnable

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
    public func fetchPackages(at sourcePath:String, forLinux:Bool = false, inDockerImage imageName:String? = "saltzmanjoelh/swiftubuntu") throws -> DockerProcessResult {
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
    public func build(source sourcePath:String, usingConfiguration configuration:BuildConfiguration, inDockerImage imageName:String = "saltzmanjoelh/swiftubuntu") throws -> DockerProcessResult {
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
    public func clean(sourcePath:String) throws -> DockerProcessResult {
        //We can use Process instead of firing up Docker because the end result is the same. A clean .build dir
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/swift build --clean"])
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
    public func create(archive archivePath:String, files filePaths:[String], flatList:Bool = true) throws -> DockerProcessResult {
        let args = flatList ? filePaths.flatMap{ return ["-C", URL(fileURLWithPath:$0).deletingLastPathComponent().path, URL(fileURLWithPath:$0).lastPathComponent] } : filePaths
        let arguments = ["-cvzf", archivePath]+args
        let result = Process.run("/usr/bin/tar", arguments: arguments)
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.createArchive(message: "Error creating archive: \(error)")
        }
        return result
    }
    
    //Currently requires aws cli tool, use like cp {source} s3://{destination}
    //TODO: use REST API
    @discardableResult
    public func upload(archive archivePath:String, to s3Path:String, using awsCliPath:String = "/usr/local/bin/aws") throws -> DockerProcessResult {
        let result = Process.run(awsCliPath, arguments: ["s3", "cp", archivePath, s3Path])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.uploadArchive(message: "Error uploading archive: \(error)")
        }
        return result
    }
    
//    func commit(to branch:String, tag)
}


// MARK: CLI Options
extension XcodeHelper: CLIRunnable {
    
    public var description: String? {
        get {
            return "Usage: xchelper COMMAND [options]"
        }
    }
    public var cliOptionGroups: [CLIOptionGroup] {
        get {
            var fetchPackages = FetchPackagesOption.command
            fetchPackages.requiredArguments = [FetchPackagesOption.sourcePath]
            fetchPackages.optionalArguments = [FetchPackagesOption.linuxPackages, FetchPackagesOption.imageName]
            fetchPackages.action = handleFetchPackages
          
            
            return [CLIOptionGroup(description:"Commands:",
                                   options:[fetchPackages])]
        }
    }
    // MARK: FetchPackages
    struct FetchPackagesOption {
        static let command          = CLIOption(keys:["fetch-packages"],
                                                description:"Fetch the package dependencies via 'swift package fetch'",
                                                requiresValue: false)
        static let sourcePath       = CLIOption(keys:["-s", "--source-path"],
                                                description:"The root of your package to call 'swift package fetch' in")
        static let linuxPackages    = CLIOption(keys:["-l", "--linux-packages"],
                                                description:"Fetch the Linux version of the packages. Some packages have Linux specific dependencies. Some Linux dependencies are not compatible with the macOS dependencies. I `swift build --clean` is performed before they are fetched. Default is false",
                                                requiresValue:true,
                                                defaultValue:"false")
        static let imageName        = CLIOption(keys:["-i", "--image-name"],
                                                description:"The Docker image name to run the commands in. Defaults to saltzmanjoelh/swiftubuntu",
                                                requiresValue:true,
                                                defaultValue:"saltzmanjoelh/swiftubuntu")
    }
    public func handleFetchPackages(option:CLIOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[FetchPackagesOption.sourcePath.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "\(FetchPackagesOption.sourcePath.keys) not provided.")
        }
        guard let forLinux = index[FetchPackagesOption.linuxPackages.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "\(FetchPackagesOption.linuxPackages.keys) not provided.")
        }
        
        guard let imageName = index[FetchPackagesOption.imageName.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "\(FetchPackagesOption.imageName.keys) not provided.")
        }
        try fetchPackages(at:sourcePath, forLinux:(forLinux as NSString).boolValue, inDockerImage: imageName)
    }
    
    // MARK: Build
    struct BuildOption {
        static let command              = CLIOption(keys: ["build"],
                                            description: "Build a Swift package in Linux and have the build errors appear in Xcode.",
                                            requiresValue: false)
        static let sourcePath           = CLIOption(keys:["-s", "--source-path"],
                                                description:"The root of your package to call 'swift build' in")
        static let buildConfiguration   = CLIOption(keys:["-c", "--build-configuration"],
                                                description:"debug or release mode. Defaults to debug",
                                                requiresValue:true,
                                                defaultValue:"debug")
        static let imageName            = CLIOption(keys:["-i", "--image-name"],
                                                description:"The Docker image name to run the commands in. Defaults to saltzmanjoelh/swiftubuntu",
                                                requiresValue:true,
                                                defaultValue:"saltzmanjoelh/swiftubuntu")
    }
    
}
