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
extension ExpressibleByUnicodeScalarLiteral where Self: ExpressibleByStringLiteral, Self.StringLiteralType == String {
    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

extension ExpressibleByExtendedGraphemeClusterLiteral where Self: ExpressibleByStringLiteral, Self.StringLiteralType == String {
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

public enum GitTagComponent : String {
    case major = "major"
    case minor = "minor"
    case patch = "patch"
    static func from(intValue: Int) -> GitTagComponent? {
        switch intValue {
        case 0:
            return .major
        case 1:
            return .minor
        case 2:
            return .patch
        default:
            return nil
        }
    }
}

public enum XcodeHelperError : Error, CustomStringConvertible {
    case clean(message:String)
    case fetch(message:String)
    case update(message:String)
    case build(message:String, exitCode: Int32)
    case symLinkDependencies(message:String)
    case createArchive(message:String)
    case uploadArchive(message:String)
    case gitTagParse(message:String)
    case gitTag(message:String)
    case unknownOption(message:String)
    public var description : String {
        get {
            switch (self) {
                case let .clean(message): return message
                case let .fetch(message): return message
                case let .update(message): return message
                case let .build(message, _): return message
                case let .symLinkDependencies(message): return message
                case let .createArchive(message): return message
                case let .uploadArchive(message): return message
                case let .gitTagParse(message): return message
                case let .gitTag(message): return message
                case let .unknownOption(message): return message
            }
        }
    }
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
            let result = DockerProcess(command: "run", commandOptions: ["-v", "\(sourcePath):\(sourcePath)"], imageName: imageName, commandArgs: commandArgs).launch(silenceOutput: false)
            if let error = result.error, result.exitCode != 0 {
                throw XcodeHelperError.fetch(message: "Error fetching packages in Linux (\(result.exitCode)):\n\(error)")
            }
            return result
        }else{
            let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && swift package fetch"])
            if let error = result.error, result.exitCode != 0 {
                throw XcodeHelperError.fetch(message: "Error fetching packages in macOS (\(result.exitCode)):\n\(error)")
            }
            return result
        }
    }
    
    @discardableResult
    public func updatePackages(at sourcePath:String, forLinux:Bool = false, inDockerImage imageName:String? = "saltzmanjoelh/swiftubuntu") throws -> ProcessResult {
        if forLinux {
            let commandArgs = ["/bin/bash", "-c", "cd \(sourcePath) && swift package update"]
            let result = DockerProcess(command: "run", commandOptions: ["-v", "\(sourcePath):\(sourcePath)"], imageName: imageName, commandArgs: commandArgs).launch(silenceOutput: false)
            if let error = result.error, result.exitCode != 0 {
                throw XcodeHelperError.update(message: "Error updating packages in Linux (\(result.exitCode)):\n\(error)")
            }
            return result
        }else{
            let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && swift package update"])
            if let error = result.error, result.exitCode != 0 {
                throw XcodeHelperError.update(message: "Error updating packages in macOS (\(result.exitCode)):\n\(error)")
            }
            return result
        }
    }
    
    //TODO: use a data container to hold the source code so that we don't have to build everything from scratch each time
    @discardableResult
    public func build(source sourcePath:String, usingConfiguration configuration:BuildConfiguration, inDockerImage imageName:String = "saltzmanjoelh/swiftubuntu", removeWhenDone: Bool = true) throws -> ProcessResult {
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
        let result = DockerProcess(command: "run", commandOptions: [removeWhenDone ? "--rm" : "", "-v", "\(sourcePath):\(sourcePath)"], imageName: imageName, commandArgs: commandArgs).launch(silenceOutput: false)
        if let error = result.error, result.exitCode != 0 {
            throw XcodeHelperError.build(message: "Error building in Linux: \(error)", exitCode: result.exitCode)
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
    public func symLinkDependencies(sourcePath:String) throws {
        //find the xcodeproj
        let projectPath = try projectFilePath(at: sourcePath)
        
        //iterate Packages dir and create symlinks without the -Ver.sion.#
        let packagesPath = sourcePath.hasSuffix("/") ? sourcePath.appending("Packages/") : sourcePath.appending("/Packages/")
        guard FileManager.default.fileExists(atPath: packagesPath) else {
            throw XcodeHelperError.symLinkDependencies(message: "Failed to find directory: \(packagesPath)")
        }
        for directory in try FileManager.default.contentsOfDirectory(atPath: packagesPath) {
            let versionedPackageName = "\(directory)"
            if versionedPackageName.hasPrefix(".") || versionedPackageName.range(of: "-")?.lowerBound == nil {
                continue//if it begins with . or doesn't have the - in it like XcodeHelper-1.0.0, skip it
            }
            //remove the - version number from name and create sym link
            let packageName = versionedPackageName.substring(to: versionedPackageName.range(of: "-")!.lowerBound)
            let result = Process.run("/bin/ln", arguments: ["-s", packagesPath.appending(versionedPackageName), packagesPath.appending(packageName)])
            if result.exitCode != 0, let error = result.error {
                throw XcodeHelperError.clean(message: "Error cleaning: \(error)")
            }
            //update the xcode references to the symlink
            do{
                let file = try String(contentsOfFile: projectPath)
                let updatedFile = file.replacingOccurrences(of: versionedPackageName, with: packageName)
                try updatedFile.write(toFile: projectPath, atomically: false, encoding: String.Encoding.utf8)
            } catch let e {
                throw XcodeHelperError.clean(message: "Error opening project file: \(e)")
            }
        }
    }
    
    public func projectFilePath(at sourcePath:String) throws -> String {
        var xcodeProjectPath: String?
        var pbProjectPath: String?
        do{
            xcodeProjectPath = try FileManager.default.contentsOfDirectory(atPath: sourcePath).filter({ (path) -> Bool in
                path.hasSuffix(".xcodeproj")
            }).first
            guard xcodeProjectPath != nil else {
                throw XcodeHelperError.symLinkDependencies(message: "Failed to find xcodeproj at path: \(sourcePath)")
            }
        } catch let e {
            throw XcodeHelperError.symLinkDependencies(message: "Error when trying to find xcodeproj at path: \(sourcePath).\nError: \(e)")
        }
        do{
            xcodeProjectPath = "\(sourcePath)/\(xcodeProjectPath!)"
            pbProjectPath = try FileManager.default.contentsOfDirectory(atPath: xcodeProjectPath!).filter({ (path) -> Bool in
                path.hasSuffix(".pbxproj")
            }).first
            guard pbProjectPath != nil else {
                throw XcodeHelperError.symLinkDependencies(message: "Failed to find pbxproj at path: \(xcodeProjectPath)")
            }
        } catch let e {
            throw XcodeHelperError.symLinkDependencies(message: "Error when trying to find pbxproj at path: \(sourcePath).\nError: \(e)")
        }
        return "\(xcodeProjectPath!)/\(pbProjectPath!)"
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
    
    
    public func getGitTag(sourcePath:String) throws -> String {
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/git tag"])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.gitTag(message: "Error reading git tags: \(error)")
        }

        //guard let tags = result.output!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: "\n").last else {
        guard let tagStrings = result.output?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: "\n") else {
            throw XcodeHelperError.gitTag(message: "Error parsing git tags: \(result.output)")
        }
        return try largestGitTag(tagStrings: tagStrings)
    }
    
    
    public func gitTagTuple(_ tagString: String) -> (Int, Int, Int)? {
        let components = tagString.components(separatedBy: ".")
        guard components.count == 3, let major = Int(components[0]), let minor = Int(components[1]), let patch = Int(components[2]) else {
            return nil
        }
        return (major, minor, patch)
    }
    public func gitTagSortValue(_ tag:(Int, Int, Int)) -> Int {
        let multiplier = Int(ceil((Double(max(tag.0, tag.1, tag.2)) / 10) * 10))
        return tag.0*multiplier*100 + tag.1*multiplier*10 + tag.2
    }
    public func largestGitTag(tagStrings:[String]) throws -> String {
        let tags = tagStrings.flatMap(gitTagTuple)
        guard let tag = tags.sorted(by: {gitTagSortValue($0) < gitTagSortValue($1)}).last else {
            throw XcodeHelperError.gitTag(message: "Git tag not found: \(tagStrings)")
        }
        
        return "\(tag.0).\(tag.1).\(tag.2)"
    }
    
    @discardableResult
    public func incrementGitTag(components: [GitTagComponent] = [.patch], at sourcePath:String) throws -> String {
        let tag = try getGitTag(sourcePath: sourcePath)
        let oldVersionComponents = tag.components(separatedBy: ".")
        if oldVersionComponents.count != 3 {
            throw XcodeHelperError.gitTag(message: "Invalid git tag: \(tag). It should be in the format #.#.# major.minor.patch")
        }
        let newVersionComponents = oldVersionComponents.enumerated().map { (offset: Int, element: String) -> String in
            if let component = GitTagComponent.from(intValue: offset), components.contains(component) {
                if let newValue = Int(element) {
                    return String(describing: newValue+1)
                }
            }
            return element
        }
        let updatedTag = newVersionComponents.joined(separator: ".")
        try gitTag(tag: updatedTag, at: sourcePath)
        
        return try getGitTag(sourcePath: sourcePath)
    }
    
    public func gitTag(tag: String, at sourcePath:String) throws {
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/git tag \(tag)"])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.gitTag(message: "Error tagging git repo: \(error)")
        }
    }
    
    public func pushGitTag(tag: String, at sourcePath:String) throws {
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/git push origin && /usr/bin/git push origin \(tag)"])
        if let error = result.error, result.exitCode != 0 || !error.contains("new tag") {
            throw XcodeHelperError.gitTag(message: "Error pushing git tag: \(error)")
        }
    }
}

