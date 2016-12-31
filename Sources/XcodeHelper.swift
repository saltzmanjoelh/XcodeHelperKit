import Foundation
import SynchronousProcess
import DockerProcess
import S3Kit

//TODO: handle update-packages when there is no existing Packages dir
//TODO: add -g option to generate-xcodeproj
//TODO: add -s option to symlink dependencies

public enum XcodeHelperError : Error, CustomStringConvertible {
    case clean(message:String)
    //    case fetch(message:String)
    case update(message:String)
    case build(message:String, exitCode: Int32)
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
            case let .build(message, _): return message
            case let .clean(message): return message
            case let .update(message): return message
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
    
    let dockerRunnable: DockerRunnable.Type
    let dateFormatter = DateFormatter()
    
    public init(dockerRunnable: DockerRunnable.Type = DockerProcess.self) {
        self.dockerRunnable = dockerRunnable
    }
    
    //MARK: Update Packages
    @discardableResult
    public func updatePackages(at sourcePath: String, using dockerImageName: String?) throws -> ProcessResult {
        if let dockerImage = dockerImageName {
            return try updateDockerPackages(at: sourcePath, in: dockerImage)
        }else{
            return try updateMacOsPackages(at: sourcePath)
        }
    }
    func updateDockerPackages(at sourcePath: String, in dockerImageName: String = "saltzmanjoelh/swiftubuntu") throws -> ProcessResult {
        let commandArgs = ["/bin/bash", "-c", "cd \(sourcePath) && swift package update"]
        let result = dockerRunnable.init(command: "run", commandOptions: ["--rm", "-v", "\(sourcePath):\(sourcePath)"], imageName: dockerImageName, commandArgs: commandArgs).launch(printOutput: true)
        if let error = result.error, result.exitCode != 0 {
            throw XcodeHelperError.update(message: "Error updating packages in Linux (\(result.exitCode)):\n\(error)")
        }
        return result
    }
    func updateMacOsPackages(at sourcePath: String) throws -> ProcessResult {
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && swift package update"])
        if let error = result.error, result.exitCode != 0 {
            throw XcodeHelperError.update(message: "Error updating packages in macOS (\(result.exitCode)):\n\(error)")
        }
        return result
    }
    
    //MARK: Build
    //TODO: add feature to only build on success by parsing logs (ProcessInfo.processInfo.environment["BUILD_DIR"]../../)
    //          Logs/Build/Cache.db is plist with most recent build in it with a highLevelStatus S or E, most recent build at top
    //          there is also a log file that ends in Succeeded or Failed, most recent one is ls -t *.xcactivitylog
    @discardableResult
    public func dockerBuild(_ sourcePath:String, with runOptions: [DockerRunOption]?, using configuration: BuildConfiguration, in dockerImageName:String = "saltzmanjoelh/swiftubuntu", persistentBuildDirectory: String? = nil) throws -> ProcessResult {
        
        //check if we need to clean first
        if try shouldClean(sourcePath: sourcePath, using: configuration) {
            try clean(sourcePath: sourcePath)
        }
        var combinedRunOptions = [String]()
        if let dockerRunOptions = runOptions {
            combinedRunOptions += dockerRunOptions.flatMap{ $0.processValues } + ["-v", "\(sourcePath):\(sourcePath)", "--workdir", sourcePath]
        }
        if persistentBuildDirectory != nil {
            combinedRunOptions += try persistentBuildOptions(at: sourcePath, using: persistentBuildDirectory!).flatMap{$0.processValues}
        }
        let bashCommand = ["/bin/bash", "-c", "swift build --configuration \(configuration.stringValue)"]
        let result = DockerProcess(command: "run", commandOptions: combinedRunOptions, imageName: dockerImageName, commandArgs: bashCommand).launch(printOutput: true)
        if let error = result.error, result.exitCode != 0 {
            throw XcodeHelperError.build(message: "Error building in Docker: \(error)", exitCode: result.exitCode)
        }
        return result
    }
    //persistentBuildDirectory is a subdirectory of .build and we mount it with .build/persistentBuildDirectory/.build:sourcePath/.build and .build/buildDirName/.Packages:sourcePath/Packages so that we can use it's artifacts for future builds and don't have to keep rebuilding
    func persistentBuildOptions(at sourcePath: String, using directoryName: String) throws -> [DockerRunOption] {
        // SomePackage/.build/
        let buildSubdirectory = URL(fileURLWithPath: sourcePath)
                                .appendingPathComponent(".build", isDirectory: true)
                                .appendingPathComponent(directoryName, isDirectory: true)
        // SomePackage/.build/platform
        return [try persistentVolume(".build", in: buildSubdirectory),
                try persistentVolume("Packages", in: buildSubdirectory)]
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
    public func clean(sourcePath:String) throws -> ProcessResult {
        //We can use Process instead of firing up Docker because the end result is the same. A clean .build dir
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/swift build --clean"])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.clean(message: "Error cleaning: \(error)")
        }
        return result
    }
    
    //TODO: add generateXcodeProject with -d option to add a xchelper docker-build build phase and -s to only build after successful macOS builds
    
    //MARK: Symlink Dependencies
    //useful for your project so that you don't have to keep updating paths for your dependencies when they change
    @discardableResult
    public func symlinkDependencies(_ sourcePath:String) throws {
        //iterate Packages dir and create symlinks without the -Ver.sion.#
        let packagesURL = URL(fileURLWithPath: sourcePath).appendingPathComponent("Packages")
        for versionedPackageName in try packageNames(from: sourcePath) {
            if let symlinkName = try symlink(dependencyPath: packagesURL.appendingPathComponent(versionedPackageName).path) {
                //update the xcode references to the symlink
                try updateXcodeReferences(for: versionedPackageName, at: sourcePath, using: symlinkName)
            }
        }
    }
    func packageNames(from sourcePath: String) throws -> [String] {
        //find the Packages directory
        let packagesPath = URL(fileURLWithPath: sourcePath).appendingPathComponent("Packages").path
        guard FileManager.default.fileExists(atPath: packagesPath)  else {
            throw XcodeHelperError.symlinkDependencies(message: "Failed to find directory: \(packagesPath)")
        }
        return try FileManager.default.contentsOfDirectory(atPath: packagesPath)
    }
    func symlink(dependencyPath: String) throws -> String? {
        let directory = URL(fileURLWithPath: dependencyPath).lastPathComponent
        if directory.hasPrefix(".") || directory.range(of: "-")?.lowerBound == nil {
            //if it begins with . or doesn't have the - in it like XcodeHelper-1.0.0, skip it
            return nil
        }
        //remove the - version number from name and create sym link
        let packagesURL = URL(fileURLWithPath: dependencyPath.substring(to: dependencyPath.range(of: "Packages", options: .backwards)!.upperBound))
        let packageName = directory.substring(to: directory.range(of: "-", options: .backwards)!.lowerBound)
        let sourcePath = packagesURL.appendingPathComponent(directory).path
        let newPath = packagesURL.appendingPathComponent(packageName).path
        do{
            //create the symlink
            if !FileManager.default.fileExists(atPath: newPath){
                let symlinkURL = URL(fileURLWithPath: newPath)
                let destinationURL = URL(fileURLWithPath: sourcePath)
                try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: destinationURL)
                print("\(symlinkURL.path) -> \(destinationURL.lastPathComponent)")
            }
        } catch let e {
            throw XcodeHelperError.clean(message: "Error creating symlink: \(e)")
        }
        
        return packageName
    }
    func updateXcodeReferences(for versionedPackageName: String, at sourcePath: String, using symlinkName: String) throws {
        //find the xcodeproj
        let projectPath = try projectFilePath(for: sourcePath)
        //open the project
        let file = try String(contentsOfFile: projectPath)
        //replace versioned package name with symlink name
        let updatedFile = file.replacingOccurrences(of: versionedPackageName, with: symlinkName)
        //save the project
        try updatedFile.write(toFile: projectPath, atomically: false, encoding: String.Encoding.utf8)
    }
    
    public func projectFilePath(for sourcePath:String) throws -> String {
        var xcodeProjectPath: String?
        var pbProjectPath: String?
        do{
            xcodeProjectPath = try FileManager.default.contentsOfDirectory(atPath: sourcePath).filter({ (path) -> Bool in
                path.hasSuffix(".xcodeproj")
            }).first
            guard xcodeProjectPath != nil else {
                throw XcodeHelperError.symlinkDependencies(message: "Failed to find xcodeproj at path: \(sourcePath)")
            }
        } catch let e {
            throw XcodeHelperError.symlinkDependencies(message: "Error when trying to find xcodeproj at path: \(sourcePath).\nError: \(e)")
        }
        do{
            xcodeProjectPath = "\(sourcePath)/\(xcodeProjectPath!)"
            pbProjectPath = try FileManager.default.contentsOfDirectory(atPath: xcodeProjectPath!).filter({ (path) -> Bool in
                path.hasSuffix(".pbxproj")
            }).first
            guard pbProjectPath != nil else {
                throw XcodeHelperError.symlinkDependencies(message: "Failed to find pbxproj at path: \(xcodeProjectPath)")
            }
        } catch let e {
            throw XcodeHelperError.symlinkDependencies(message: "Error when trying to find pbxproj at path: \(sourcePath).\nError: \(e)")
        }
        return "\(xcodeProjectPath!)/\(pbProjectPath!)"
    }
    
    //MARK: Create Archive
    @discardableResult
    public func createArchive(at archivePath:String, with filePaths:[String], flatList:Bool = true) throws -> ProcessResult {
        try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: archivePath).deletingLastPathComponent().path, withIntermediateDirectories: true, attributes: nil)
        let args = flatList ? filePaths.flatMap{ return ["-C", URL(fileURLWithPath:$0).deletingLastPathComponent().path, URL(fileURLWithPath:$0).lastPathComponent] } : filePaths
        let arguments = ["-cvzf", archivePath]+args
        let result = Process.run("/usr/bin/tar", arguments: arguments)
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.createArchive(message: "Error creating archive: \(error)")
        }
        return result
    }
    
    //MARK: Upload Archive
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
    
    //MARK: Git Tag
    public func getGitTag(at sourcePath:String) throws -> String {
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/git tag"], printOutput: false)
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
        let tags = tagStrings.flatMap(gitTagTuple)
        guard let tag = tags.sorted(by: {gitTagCompare($0, $1)}).last else {
            throw XcodeHelperError.gitTag(message: "Git tag not found: \(tagStrings)")
        }
        
        return "\(tag.0).\(tag.1).\(tag.2)"
    }
    
    @discardableResult
    public func incrementGitTag(component targetComponent: GitTagComponent = .patch, at sourcePath: String) throws -> String {
        let tag = try getGitTag(at: sourcePath)
        let oldVersionComponents = tag.components(separatedBy: ".")
        if oldVersionComponents.count != 3 {
            throw XcodeHelperError.gitTag(message: "Invalid git tag: \(tag). It should be in the format #.#.# major.minor.patch")
        }
        let newVersionComponents = oldVersionComponents.enumerated().map { (oldComponentValue: Int, oldStringValue: String) -> String in
            if oldComponentValue == targetComponent.rawValue, let oldIntValue = Int(oldStringValue) {
                return String(describing: oldIntValue+1)
            }else{
                return oldComponentValue > targetComponent.rawValue ? "0" : oldStringValue
            }
        }
        let updatedTag = newVersionComponents.joined(separator: ".")
        try gitTag(updatedTag, repo: sourcePath)
        
        return try getGitTag(at: sourcePath)
    }
    
    public func gitTag(_ tag: String, repo sourcePath: String) throws {
        let result = Process.run("/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/git tag \(tag)"], printOutput: false)
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
    
    //MARK: Create XCArchive
    //returns a String for the path of the xcarchive
    public func createXcarchive(in dirPath: String, with binaryPath: String, from schemeName: String) throws -> String {
        let name = URL(fileURLWithPath: binaryPath).lastPathComponent
        let directoryDate = xcarchiveDirectoryDate(from: dateFormatter)
        let archiveDate = xcarchiveDate(from: dateFormatter)
        let archiveName = "xchelper-\(name) \(archiveDate).xcarchive"
        let path = "\(dirPath)/\(directoryDate)/\(archiveName)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        try createXcarchivePlist(in: path, name: name, schemeName: schemeName)
        try createArchive(at: path.appending("/Products/\(name).tar"), with: [binaryPath])
        return path
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
        let date = xcarchivePlistDateString(formatter: dateFormatter)
        let dictionary = ["ArchiveVersion": "2",
                          "CreationDate": date,
                          "Name": name,
                          "SchemeName": schemeName] as NSDictionary
        do{
            let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
            try data.write(to: URL.init(fileURLWithPath: dirPath.appending("/Info.plist")) )
        }catch let e{
            throw XcodeHelperError.xcarchivePlist(message: "Failed to create plist in: \(dirPath). Error: \(e)")
        }
    }
    
}

