//xcode -> swift package fetch
//PreBuild -> Packages/XcodeHelpers*/ 

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

enum XcodeHelperError : Error {
    case clean(message:String)
    case build(message:String)
    case updateSymLinks(message:String)
    case createArchive(message:String)
    case uploadArchive(message:String)
}

struct XcodeHelper {
    
    func bash(command:String) throws -> [String] {
        return ["/bin/bash", "-c", command]
    }
    func build(source sourcePath:String, usingConfiguration configuration:BuildConfiguration, inDockerImage imageName:String = "saltzmanjoelh/swiftubuntu") throws {
        //check if we need to clean first
        if try shouldClean(sourcePath:sourcePath, forConfiguration:configuration) {
            try clean(sourcePath: sourcePath)
        }
        //At the moment, building directly from a mounted volume gives errors like "error: Could not create file ... /.Package.toml"
        //rsync the files to the root of the disk (excluding .build dir) the replace the build
//        let buildDir = configuration.buildDirectory(inSourcePath: sourcePath)
//        let commandArgs = ["/bin/bash", "-c", "rsync -ar --exclude=\(buildDir) --exclude=*.git \(sourcePath) /source && cd /source && swift build && rsync -ar /source/ \(sourcePath)"]
        //simple build doesn't work
        let commandArgs = ["/bin/bash", "-c", "hostname && cd \(sourcePath) && pwd && ls -al && swift build"]
        let result = DockerToolboxTask(command: "run", commandOptions: ["-v", "\(sourcePath):\(sourcePath)"], imageName: imageName, commandArgs: commandArgs).launch(silenceOutput: false)
        if let error = result.error, result.exitCode != 0 {
            throw XcodeHelperError.build(message: "Error building in Linux (\(result.exitCode)):\n\(error)")
        }
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
    
    func clean(sourcePath:String) throws {
        //We can use Task instead of firing up Docker because the end result is the same. A clean .build dir
        let result = Task.run(launchPath: "/bin/bash", arguments: ["-c", "cd \(sourcePath) && /usr/bin/swift build --clean"])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.clean(message: "Error cleaning: \(error)")
        }
    }
    
    //useful for your project so that you don't have to keep updating paths for your dependencies when they change
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
    
    func create(archive archivePath:String, files filePaths:[String], flatList:Bool) throws {
        let args = flatList ? filePaths.flatMap{ return ["-C", URL(fileURLWithPath:$0).deletingLastPathComponent().path, URL(fileURLWithPath:$0).lastPathComponent] } : filePaths
        let arguments = ["-cvzf", archivePath]+args
        let result = Task.run(launchPath: "/usr/bin/tar", arguments: arguments)
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.createArchive(message: "Error creating archive: \(error)")
        }
    }
    
    //Currently requires aws cli tool
    //TODO: use REST API
    func upload(archive archivePath:String, to s3Bucket:String, using awsCliPath:String) throws {
        let archiveName = URL(fileURLWithPath:archivePath).lastPathComponent
        let result = Task.run(launchPath: awsCliPath, arguments: ["s3", "cp", archivePath, "s3://\(s3Bucket)/\(archiveName)" ])
        if result.exitCode != 0, let error = result.error {
            throw XcodeHelperError.uploadArchive(message: "Error uploading archive: \(error)")
        }
    }
//    #upload archive from osx
//    if [ "${ACTION}" == "install" ]; then
//    cd $PROJECT_DIR
//    if [ -f "${S3_ARCHIVE_NAME}" ]; then
//    $AWS_CLI s3 cp "${S3_ARCHIVE_NAME}" "s3://${S3_BUCKET_ROOT}.${BRANCH_NAME}/${S3_ARCHIVE_NAME}"
//    rm "${S3_ARCHIVE_NAME}"
//    else echo "Archive (${S3_ARCHIVE_NAME}) not found."; ls -al
//    fi
//    fi
    
//    func commit(to branch:String, tag)
}
