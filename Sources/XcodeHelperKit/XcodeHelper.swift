import Foundation
import ProcessRunner
import DockerProcess
import S3Kit

public enum XcodeHelperError : Error, CustomStringConvertible {
    case clean(message:String)
    //    case fetch(message:String)
    case updatePackages(message:String)
    case dockerBuild(message:String, exitCode: Int32)
    case symlinkDependencies(message:String)
    case createArchive(message:String)
    case uploadArchive(message:String)
    case gitTagParse(message:String)
    case gitTag(message:String)
    case createXcarchive(message:String)
    case xcarchivePlist(message: String)
    case unknownOption(message:String)
    public var description : String {
        get {
            switch (self) {
            case let .dockerBuild(message, _): return message
            case let .clean(message): return message
            case let .updatePackages(message): return message
            case let .symlinkDependencies(message): return message
            case let .createArchive(message): return message
            case let .uploadArchive(message): return message
            case let .gitTagParse(message): return message
            case let .gitTag(message): return message
            case let .createXcarchive(message): return message
            case let .xcarchivePlist(message): return message
            case let .unknownOption(message): return message
            }
        }
    }
}

/*public enum DockerEnvironmentVariable: String {
 case projectName = "PROJECT"
 case projectDirectory = "PROJECT_DIR"
 case commandOptions = "DOCKER_COMMAND_OPTIONS"
 case imageName = "DOCKER_IMAGE_NAME"
 case containerName = "DOCKER_CONTAINER_NAME"
 }*/


public struct XcodeHelper: XcodeHelpable {
//    public static let logsSubDirectory = ".xcodehelper_logs"
    public static var logger: Logger?
    let dockerRunnable: DockerRunnable.Type
    let processRunnable: ProcessRunnable.Type
    let dateFormatter = DateFormatter()
    
    
    public init(dockerRunnable: DockerRunnable.Type = DockerProcess.self, processRunnable: ProcessRunnable.Type = ProcessRunner.self) {
        self.dockerRunnable = dockerRunnable
        self.processRunnable = processRunnable
    }
    
    public func packagesURL(at sourcePath: String) -> URL {
        return URL(fileURLWithPath: sourcePath).appendingPathComponent(".build").appendingPathComponent("checkouts")
    }
    
    //MARK: Update Packages
    // The combination of `swift package update` and persistentVolume caused "segmentation fault" and swift compiler crashes
    // For now, when we update packages in Docker we should delete all existing packages first. ie: don't persist Packges directory
    @discardableResult
    public func updateDockerPackages(at sourcePath: String, inImage dockerImageName: String, withVolume persistentVolumeName: String, shouldLog: Bool = true) throws -> ProcessResult {
        XcodeHelper.logger = Logger(category: Command.updateDockerPackages.title)
        XcodeHelper.logger?.logWithNotification("Updating Docker packages at: %@", sourcePath)
        
        //        //backup the Packages dir
        //        movePackages(at: sourcePath, fromBackup: false)
        
        //Update the Docker Packages
        let commandArgs = ["/bin/bash", "-c", "swift package update"]
        var commandOptions: [DockerRunOption] = [.volume(source: sourcePath, destination: sourcePath),//include the sourcePath
            .workingDirectory(at: sourcePath)]//move to the sourcePath
        commandOptions += try persistentVolumeOptions(at: sourcePath, using: persistentVolumeName)//overwrite macOS .build with persistent volume for docker's .build dir
        var dockerProcess = dockerRunnable.init(command: "run", commandOptions: commandOptions.flatMap{ $0.processValues }, imageName: dockerImageName, commandArgs: commandArgs)
        dockerProcess.processRunnable = self.processRunnable
        let result = dockerProcess.launch(printOutput: true, outputPrefix: dockerImageName)
        if let error = result.error, result.exitCode != 0 {
            let message = "\(persistentVolumeName) - Error updating packages\n\(error)"
            if error.count > 1 {
                XcodeHelper.logger?.error("%@", message)
            }
            throw XcodeHelperError.updatePackages(message: message)
        }
        
        //        //Restore the Packages directory
        //        movePackages(at: sourcePath, fromBackup: true)
        XcodeHelper.logger?.logWithNotification("Packages updated.")
        return result
    }
    func movePackages(at sourcePath: String, fromBackup: Bool) {
        let originalURL = packagesURL(at: sourcePath)
        let backupURL = originalURL.appendingPathExtension("backup")
        let arguments = fromBackup ? [backupURL.path, originalURL.path] : [originalURL.path, backupURL.path]
        
        processRunnable.synchronousRun("/bin/mv", arguments: arguments, printOutput: false, outputPrefix: nil, environment: nil)
    }
    
    @discardableResult
    public func updateMacOsPackages(at sourcePath: String, shouldLog: Bool = true) throws -> ProcessResult {
        XcodeHelper.logger = Logger(category: Command.updateMacOSPackages.title)
        XcodeHelper.logger?.logWithNotification("Updating macOS packages at: %@" as StaticString, (sourcePath as NSString).lastPathComponent)
        let result = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath) && swift package update"])
        if let error = result.error, result.exitCode != 0 {
            let message = "Error updating packages\n\(error)"
//            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.updatePackages(message: message)
        }
        XcodeHelper.logger?.logWithNotification("Packages updated")
        return result
    }
    @available(OSX 10.11, *)
    public func recursivePackagePaths(at sourcePath: String) -> [String] {
        guard let contents = FileManager.default.recursiveContents(of: URL(fileURLWithPath: sourcePath))
            else { return [sourcePath] }
        let urls: [String] = contents.compactMap{ (url: URL) in
            return url.lastPathComponent == "Package.swift" && !url.path.contains("/.") ? url.path : nil
        }
        return urls.count > 0 ? urls : [sourcePath]
    }
    
    @discardableResult
    public func generateXcodeProject(at sourcePath: String, shouldLog: Bool = true) throws -> ProcessResult {
        XcodeHelper.logger?.log("Generating Xcode Project")
        let result = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath) && swift package generate-xcodeproj"])
        if let error = result.error {
            let message = "Error generating Xcode project (\(result.exitCode):\n\(error)"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.updatePackages(message: message)
        }
        XcodeHelper.logger?.log("Xcode project generated")
        return result
    }
    
    //MARK: Build
    @discardableResult
    public func dockerBuild(_ sourcePath:String, with runOptions: [DockerRunOption]?, using configuration: BuildConfiguration, in dockerImageName:String = "swift", persistentVolumeName: String? = nil, shouldLog: Bool = true) throws -> ProcessResult {
        XcodeHelper.logger = Logger(category: Command.dockerBuild.title)
        XcodeHelper.logger?.logWithNotification("Building in Docker - %@", dockerImageName)
        //We are using separate .build directories for each platform now.
        //We don't need to clean
        //        //check if we need to clean first
        //        if try shouldClean(sourcePath: sourcePath, using: configuration) {
        //            XcodeHelper.logger?.log("Cleaning", for: command)
        //            try clean(sourcePath: sourcePath)
        //        }
        
        var combinedRunOptions = [String]()
        if let dockerRunOptions = runOptions {
            combinedRunOptions += dockerRunOptions.flatMap{ $0.processValues } + ["-v", "\(sourcePath):\(sourcePath)", "--workdir", sourcePath]
            if let containerName = containerNameToRemove(dockerRunOptions) {
                removeContainer(named: containerName)
            }
        }
        if let volumeName = persistentVolumeName {
            combinedRunOptions += try persistentVolumeOptions(at: sourcePath, using: volumeName).flatMap{$0.processValues}
        }
        let bashCommand = ["/bin/bash", "-c", "cd \(sourcePath) && swift build --configuration \(configuration.stringValue)"]
        let result = DockerProcess(command: "run", commandOptions: combinedRunOptions, imageName: dockerImageName, commandArgs: bashCommand).launch(printOutput: true)
        if let error = result.error, result.exitCode != 0 {
            let prefix = persistentVolumeName != nil ? "\(persistentVolumeName!) - " : ""
            let message = "\(prefix) Error building in Docker: \(error)"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.dockerBuild(message: message,
                                               exitCode: result.exitCode)
        }
        XcodeHelper.logger?.logWithNotification("Done building")
        return result
    }
    //persistentBuildDirectory is a subdirectory of .build and we mount it with .build/persistentBuildDirectory/.build:sourcePath/.build and .build/buildDirName/.Packages:sourcePath/Packages so that we can use it's artifacts for future builds and don't have to keep rebuilding
    func persistentVolumeOptions(at sourcePath: String, using directoryName: String) throws -> [DockerRunOption] {
        // SomePackage/.build/
        let buildSubdirectory = URL(fileURLWithPath: sourcePath)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        // SomePackage/.build/platform
        //not persisting Packages directory for now since it causes swift compiler to crash
        return [try persistentVolume(".build", in: buildSubdirectory)]//try persistentVolume("Packages", in: buildSubdirectory)]
        
    }
    func persistentVolume(_ name: String, in buildSubdirectory: URL) throws -> DockerRunOption {
        // SomePackage/.build/platform
        let sourceDirectory = buildSubdirectory.appendingPathComponent(name, isDirectory: true)// SomePackage/.build/platform/.build
        let destinationDirectory = buildSubdirectory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)// SomePackage/.build/
        
        
        //make sure that the persistent directories exist before we return volume mount points
        if !FileManager.default.fileExists(atPath: sourceDirectory.path) {
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        return .volume(source: sourceDirectory.path, destination: destinationDirectory.path)
    }
    func containerNameToRemove(_ dockerRunOptions: [DockerRunOption]) -> String? {
        guard dockerRunOptions.contains(where: { (runOption: DockerRunOption) -> Bool in
            return runOption.processValues == DockerRunOption.removeWhenDone.processValues
        }) else { return nil }
        
        guard let containerNameFlag = DockerRunOption.container(name: "").processValues.first, //--name
            let containerNameOption = dockerRunOptions.first(where: { (runOption: DockerRunOption) -> Bool in
            return runOption.processValues.contains(containerNameFlag)
        }) else { return nil }
        
        return containerNameOption.processValues.last
    }
    func removeContainer(named containerName: String) {
        let process = DockerProcess.init(command: "rm", commandOptions: ["-f", "-v", containerName])
        process.launch()
    }
    
    //MARK: Clean
    public func shouldClean(sourcePath: String, using configuration: BuildConfiguration) throws -> Bool {
        let yamlPath = configuration.yamlPath(inSourcePath:sourcePath)
        if FileManager.default.isReadableFile(atPath: yamlPath) {
            let yamlFile = try String(contentsOfFile: yamlPath)
            return yamlFile.contains("\"-target\",\"x86_64-apple")//if we have a file and it contains apple target, clean
        }
        
        //otherwise, clean if there is a build path but the file isn't readable
        return FileManager.default.fileExists(atPath: configuration.buildDirectory(inSourcePath: sourcePath))
    }
    
    @discardableResult
    public func clean(sourcePath:String, shouldLog: Bool = true) throws -> ProcessResult {
        XcodeHelper.logger?.log("Cleaning")
        //We can use Process instead of firing up Docker because the end result is the same. A clean .build dir
        let result = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/swift build --clean"])
        if result.exitCode != 0, let error = result.error {
            let message = "Error cleaning: \(error)"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.clean(message: message)
        }
        return result
    }
    
    //MARK: Symlink Dependencies
    //useful for your project so that you don't have to keep updating paths for your dependencies when they change
    public func symlinkDependencies(at sourcePath:String, shouldLog: Bool = true) throws {
        XcodeHelper.logger?.log("Symlinking dependencies")
        //iterate Packages dir and create symlinks without the -Ver.sion.#
        let url = packagesURL(at: sourcePath)
        for versionedPackageName in try packageNames(from: sourcePath) {
            if let symlinkName = try symlink(dependencyPath: url.appendingPathComponent(versionedPackageName).path) {
                XcodeHelper.logger?.log("Symlink: %@ -> %@", symlinkName, url.appendingPathComponent(versionedPackageName).path)
                //update the xcode references to the symlink
                do {
                    try updateXcodeReferences(for: url.appendingPathComponent(versionedPackageName),
                                              at: sourcePath,
                                              using: symlinkName)
                    XcodeHelper.logger?.log("Updated Xcode references")
                }catch let e{
                    XcodeHelper.logger?.log("%@", String(describing: e))
                    throw e
                }
            }
        }
        XcodeHelper.logger?.log("Symlinking done")
    }
    func packageNames(from sourcePath: String) throws -> [String] {
        //find the Packages directory
        let packagesPath = URL(fileURLWithPath: sourcePath).appendingPathComponent(".build").appendingPathComponent("checkouts").path
        guard FileManager.default.fileExists(atPath: packagesPath)  else {
            throw XcodeHelperError.symlinkDependencies(message: "Failed to find directory: \(packagesPath)")
        }
        return try FileManager.default.contentsOfDirectory(atPath: packagesPath)
    }
    func symlink(dependencyPath: String) throws -> String? {
        let directory = URL(fileURLWithPath: dependencyPath).lastPathComponent
        guard !directory.hasPrefix("."),
            !directory.hasSuffix("json"),
            let symlinkName = symlinkNameFromDependencyDirectory(directory)
            else {
                return nil //if it begins with . or doesn't have the - in it like XcodeHelper-7587831595904724403, skip it
        }
        //remove the - version number from name and create sym link
        let packagesURL = URL(fileURLWithPath: dependencyPath).deletingLastPathComponent()
        let sourcePath = packagesURL.appendingPathComponent(directory).path
        let newPath = packagesURL.appendingPathComponent(symlinkName).path
        do{
            //create the symlink
            if FileManager.default.fileExists(atPath: newPath) {
                //delete the existing file each time in case it gets corrupt
                //I have seen files that don't correctly registre with FileManager as files, not sure what happened with it
                try? FileManager.default.removeItem(atPath: newPath)
            }
            let symlinkURL = URL(fileURLWithPath: newPath)
            let destinationURL = URL(fileURLWithPath: sourcePath)
            try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: destinationURL)
        } catch let e {
            throw XcodeHelperError.clean(message: "Error creating symlink: \(e)")
        }
        
        return symlinkName
    }
    //Directory can either be "ProcessRunner.git-7587831595904724403" or "ProcessRunner-7587831595904724403"
    //Either way, we are looking for the last hyphen
    func symlinkNameFromDependencyDirectory(_ directory: String) -> String? {
        guard let hyphenRange = directory.range(of: "-", options: .backwards) else { return nil }
        let checkoutPrefix = String(directory[directory.startIndex..<hyphenRange.lowerBound])
        //checkoutPrefix can contain ".git-" or ".git--"
        if let gitRange = checkoutPrefix.range(of: ".git", options: .backwards) {
            return String(checkoutPrefix[checkoutPrefix.startIndex..<gitRange.lowerBound])
        }
        return String(checkoutPrefix)
    }
    func updateXcodeReferences(for versionedPackageURL: URL, at sourcePath: String, using symlinkName: String) throws {
        //find the xcodeproj
        let projectPath = try projectFilePath(for: sourcePath)
        //open the project
        let file = try String(contentsOfFile: projectPath)
        //replace versioned group name with package name
        guard let packageName = getPackageName(versionedPackageURL.lastPathComponent, from: file) else { return }
        let gitTag = try getGitTag(at: versionedPackageURL.path, shouldLog: false)
        var updatedFile = file.replacingOccurrences(of: "\(packageName) \(gitTag)", with: packageName)
        //replace versioned package name with symlink name
        updatedFile = updatedFile.replacingOccurrences(of: versionedPackageURL.lastPathComponent, with: symlinkName)
        //save the project
        try updatedFile.write(toFile: projectPath, atomically: false, encoding: String.Encoding.utf8)
    }
    func getPackageName(_ checkoutName: String, from pbxFile: String) -> String? {
        //Repo could have "XcodeHelperCli.git-8182514958374350212"
        // but project name is "XcodeHelperCliKit" and has a folder reference as "XcodeHelperCliKit 1.0.3"
        //Find the obj with
        //  path = ".build/checkouts/XcodeHelperCli.git-8182514958374350212/Sources/XcodeHelperCliKit";
        //return the last path
        
        let regex = try! NSRegularExpression.init(pattern: ".build/checkouts/\(checkoutName)/Sources(.*?)\"", options: [])
        let pathRange = regex.rangeOfFirstMatch(in: pbxFile, options: [], range: NSMakeRange(0, pbxFile.count))
        guard pathRange.location != NSNotFound else { return nil }
        let path = pbxFile[pbxFile.index(pbxFile.startIndex, offsetBy: pathRange.lowerBound)..<pbxFile.index(pbxFile.startIndex, offsetBy: pathRange.upperBound-1)]
        let url = URL.init(fileURLWithPath: String(path))
        let packageName = url.lastPathComponent
        
        return packageName
    }
    
    public func projectFilePath(for sourcePath:String) throws -> String {
        var xcodeProjectPath: String?
        var pbProjectPath: String?
        do{
            xcodeProjectPath = try FileManager.default.contentsOfDirectory(atPath: sourcePath).filter({ (path) -> Bool in
                path.hasSuffix(".xcodeproj")
            }).first
            guard xcodeProjectPath != nil else {
                let message = "Failed to find xcodeproj at path: \(sourcePath)"
                XcodeHelper.logger?.log("%@", message)
                throw XcodeHelperError.symlinkDependencies(message: message)
            }
        } catch let e {
            let message = "Error when trying to find xcodeproj at path: \(sourcePath).\nError: \(String(describing: e))"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.symlinkDependencies(message: message)
        }
        do{
            xcodeProjectPath = "\(sourcePath)/\(xcodeProjectPath!)"
            pbProjectPath = try FileManager.default.contentsOfDirectory(atPath: xcodeProjectPath!).filter({ (path) -> Bool in
                path.hasSuffix(".pbxproj")
            }).first
            guard pbProjectPath != nil else {
                let message = "Failed to find pbxproj at path: \(String(describing: xcodeProjectPath))"
                XcodeHelper.logger?.log("%@", message)
                throw XcodeHelperError.symlinkDependencies(message: message)
            }
        } catch let e {
            let message = "Error when trying to find pbxproj at path: \(sourcePath).\nError: \(String(describing: e))"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.symlinkDependencies(message: message)
        }
        return "\(xcodeProjectPath!)/\(pbProjectPath!)"
    }
    
    //MARK: Create Archive
    
    
    
    @discardableResult
    public func createArchive(at archivePath:String, with filePaths:[String], flatList:Bool = true, shouldLog: Bool = true) throws -> ProcessResult {
        XcodeHelper.logger = Logger(category: Command.createArchive.title)
        XcodeHelper.logger?.logWithNotification("Creating archive %@", archivePath)
        try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: archivePath).deletingLastPathComponent().path, withIntermediateDirectories: true, attributes: nil)
        let args = flatList ? filePaths.flatMap{ return ["-C", URL(fileURLWithPath:$0).deletingLastPathComponent().path, URL(fileURLWithPath:$0).lastPathComponent] } : filePaths
        let arguments = ["-cvzf", archivePath]+args
        let result = ProcessRunner.synchronousRun("/usr/bin/tar", arguments: arguments)
        if result.exitCode != 0, let error = result.error {
            let message = "Error creating archive: \(error)"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.createArchive(message: message)
        }
        XcodeHelper.logger?.logWithNotification("Archive created")
        return result
    }
    
    //MARK: Upload Archive
    public func uploadArchive(at archivePath:String, to s3Bucket:String, in region: String, key: String, secret: String, shouldLog: Bool = true) throws  {
        XcodeHelper.logger = Logger(category: Command.uploadArchive.title)
        XcodeHelper.logger?.logWithNotification("Uploading archve: %@", URL(fileURLWithPath: archivePath).lastPathComponent)
        let result = try S3.with(key: key, and: secret).upload(file: URL.init(fileURLWithPath: archivePath), to: s3Bucket, in: region)
        if result.response.statusCode != 200 {
            var description = result.response.description
            if let data = result.data {
                if let text = String(data: data as Data, encoding: .utf8) {
                    description += "\n\(text)"
                }
            }
            XcodeHelper.logger?.log("%@", description)
            throw XcodeHelperError.uploadArchive(message: description)
        }
        XcodeHelper.logger?.logWithNotification("Archive uploaded")
    }
    
    public func uploadArchive(at archivePath:String, to s3Bucket:String, in region: String, using credentialsPath: String, shouldLog: Bool = true) throws  {
        XcodeHelper.logger = Logger(category: Command.uploadArchive.title)
        XcodeHelper.logger?.logWithNotification("Uploading archve: %@", URL(fileURLWithPath: archivePath).lastPathComponent)
        let result = try S3.with(credentials: credentialsPath).upload(file: URL.init(fileURLWithPath: archivePath), to: s3Bucket, in: region)
        if result.response.statusCode != 200 {
            var description = result.response.description
            if let data = result.data {
                if let text = String(data: data as Data, encoding: .utf8) {
                    description += "\n\(text)"
                }
            }
            XcodeHelper.logger?.log("%@", description)
            throw XcodeHelperError.uploadArchive(message: description)
        }
        XcodeHelper.logger?.logWithNotification("Archive uploaded")
    }
    
    //MARK: Git Tag
    public func getGitTag(at sourcePath:String, shouldLog: Bool = true) throws -> String {
        XcodeHelper.logger = Logger(category: Command.gitTag.title)
        let result = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/git tag"], printOutput: false)
        if result.exitCode != 0, let error = result.error {
            let message = "Error reading git tags: \(error)"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.gitTag(message: message)
        }
        
        //guard let tags = result.output!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: "\n").last else {
        guard let tagStrings = result.output?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: "\n") else {
            let message = "Error parsing git tags: \(String(describing: result.output))"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.gitTag(message: message)
        }
        var tag: String = ""
        do {
            tag = try largestGitTag(tagStrings: tagStrings)
        }catch let e{
            XcodeHelper.logger?.log("%@", String(describing: e))
            throw e
        }
        
        if shouldLog {
            XcodeHelper.logger?.log("%@", tag)
        }
        return tag
    }
    
    
    public func gitTagTuple(_ tagString: String) -> (Int, Int, Int)? {
        let components = tagString.components(separatedBy: ".")
        guard components.count == 3, let major = Int(components[0]), let minor = Int(components[1]), let patch = Int(components[2]) else {
            return nil
        }
        return (major, minor, patch)
    }
    
    public func gitTagCompare(_ lhs:(Int, Int, Int), _ rhs: (Int, Int, Int)) -> Bool {
        if lhs.0 != rhs.0 {
            return lhs.0 < rhs.0
        }
        else if lhs.1 != rhs.1 {
            return lhs.1 < rhs.1
        }
        return lhs.2 < rhs.2
    }
    
    public func largestGitTag(tagStrings:[String]) throws -> String {
        let tags = tagStrings.compactMap(gitTagTuple)
        guard let tag = tags.sorted(by: {gitTagCompare($0, $1)}).last else {
            let message = "Git tag not found: \(tagStrings)"
            XcodeHelper.logger?.error("%@", message)
            throw XcodeHelperError.gitTag(message: message)
        }
        
        return "\(tag.0).\(tag.1).\(tag.2)"
    }
    
    @discardableResult
    public func incrementGitTag(component targetComponent: GitTagComponent = .patch, at sourcePath: String, shouldLog: Bool = true) throws -> String {
        let tag = try getGitTag(at: sourcePath, shouldLog: false)
        let oldVersionComponents = tag.components(separatedBy: ".")
        if oldVersionComponents.count != 3 {
            throw XcodeHelperError.gitTag(message: "Invalid git tag: \(tag). It should be in the format #.#.# major.minor.patch")
        }
        let newVersionComponents = oldVersionComponents.enumerated().map { (__val:(Int, String)) -> String in let (oldComponentValue,oldStringValue) = __val;
            if oldComponentValue == targetComponent.rawValue, let oldIntValue = Int(oldStringValue) {
                return String(describing: oldIntValue+1)
            }else{
                return oldComponentValue > targetComponent.rawValue ? "0" : oldStringValue
            }
        }
        let updatedTag = newVersionComponents.joined(separator: ".")
        do {
            _ = try gitTag(updatedTag, repo: sourcePath)
            
            return try getGitTag(at: sourcePath)
        }catch let e{
            XcodeHelper.logger?.log("%@", String(describing: e))
            throw e
        }
    }
    
    public func gitTag(_ tag: String, repo sourcePath: String, shouldLog: Bool = true) throws -> ProcessResult {
        let result = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/git tag \(tag)"], printOutput: false)
        if result.exitCode != 0, let error = result.error {
            let message = "Error tagging git repo: \(error)"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.gitTag(message: message)
        }
        return result
    }
    
    public func pushGitTag(tag: String, at sourcePath:String, shouldLog: Bool = true) throws {
        XcodeHelper.logger = Logger(category: Command.gitTag.title)
        XcodeHelper.logger?.log("Pushing tag: %@", tag)
        let result = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/git push origin && /usr/bin/git push origin \(tag)"])
        if let error = result.error, result.exitCode != 0 || !error.contains("new tag") {
            let message = "Error pushing git tag: \(error)"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.gitTag(message: message)
        }
        XcodeHelper.logger?.log("Pushed tag: %@", tag)
    }
    
    //MARK: Create XCArchive
    //returns a String for the path of the xcarchive
    public func createXcarchive(in dirPath: String, with binaryPath: String, from schemeName: String, shouldLog: Bool = true) throws -> ProcessResult {
        XcodeHelper.logger = Logger(category: Command.createXcarchive.title)
        XcodeHelper.logger?.logWithNotification("Creating XCAchrive %@", URL(fileURLWithPath: binaryPath).lastPathComponent)
        let name = URL(fileURLWithPath: binaryPath).lastPathComponent
        let directoryDate = xcarchiveDirectoryDate(from: dateFormatter)
        let archiveDate = xcarchiveDate(from: dateFormatter)
        let archiveName = "xchelper-\(name) \(archiveDate).xcarchive"
        let path = "\(dirPath)/\(directoryDate)/\(archiveName)"
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            try createXcarchivePlist(in: path, name: name, schemeName: schemeName)
            var result = try createArchive(at: path.appending("/Products/\(name).tar"), with: [binaryPath])
            result.output?.append("\n\(path)")
            return result
        }catch let e{
            XcodeHelper.logger?.log("%@", String(describing: e))
            throw e
        }
    }
    
    private func xcarchiveDirectoryDate(from formatter: DateFormatter, from: Date = Date()) -> String {
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return dateFormatter.string(from: from)
    }
    
    internal func xcarchiveDate(from formatter: DateFormatter, from: Date = Date()) -> String {
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "MM-dd-yyyy, h.mm.ss a"
        
        return dateFormatter.string(from: from)
    }
    
    internal func xcarchivePlistDateString(formatter: DateFormatter, from: Date = Date()) -> String {
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        
        return dateFormatter.string(from: from)
    }
    
    internal func createXcarchivePlist(in dirPath:String, name: String, schemeName:String) throws {
        XcodeHelper.logger = Logger(category: Command.createXcarchive.title)
        XcodeHelper.logger?.log("Creating Plist")
        let date = xcarchivePlistDateString(formatter: dateFormatter)
        let dictionary = ["ArchiveVersion": "2",
                          "CreationDate": date,
                          "Name": name,
                          "SchemeName": schemeName] as NSDictionary
        do{
            let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
            try data.write(to: URL.init(fileURLWithPath: dirPath.appending("/Info.plist")) )
        }catch let e{
            let message = "Failed to create plist in: \(dirPath). Error: \(e)"
            XcodeHelper.logger?.log("%@", message)
            throw XcodeHelperError.xcarchivePlist(message: message)
        }
    }
    
}

