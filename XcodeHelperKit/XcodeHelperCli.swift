//
//  XcodeHelperCli.swift
//  XcodeHelper
//
//  Created by Joel Saltzman on 8/28/16.
//
//

import Foundation
import CliRunnable

//TODO: env vars should automatically be --long-version -> LONG_VERSION

// MARK: Cli Options
extension XcodeHelper: CliRunnable {
    
    public var description: String? {
        get {
            return "Helps you stay in Xcode and off the command line. You can build and run tests on Linux through Docker, fetch Swift packages, keep your \"Dependencies\" group in Xcode referencing the correct paths and tar and upload you Linux binary to AWS S3 buckets."
        }
    }
    public var appUsage: String? {
        return "Usage: xchelper COMMAND SOURCE_CODE_PATH [OPTIONS]."
    }
    public var footerDescription: String? {
        return "Run 'xchelper COMMAND --help' for more information on a command."
    }
    

    
    public var cliOptionGroups: [CliOptionGroup] {
        get {
            var fetchPackagesOption = FetchPackages.command
            fetchPackagesOption.optionalArguments = [FetchPackages.linuxPackages, FetchPackages.imageName]
            fetchPackagesOption.action = handleFetchPackages
            
            
            return [CliOptionGroup(description:"Commands:",
                                   options:[fetchPackagesOption])]
        }
    }
    // MARK: FetchPackages
    struct FetchPackages {
        static let command          = CliOption(keys: ["fetch-packages"],
                                                description: "Fetch the package dependencies via 'swift package fetch'",
                                                usage: "xchelper fetch-packages SOURCE_CODE_PATH [OPTIONS]. SOURCE_CODE_PATH is the root of your package to call 'swift package fetch' in.")
        static let linuxPackages    = CliOption(keys:["-l", "--linux-packages", "LINUX_PACKAGES"],
                                                description:"Fetch the Linux version of the packages. Some packages have Linux specific dependencies. Some Linux dependencies are not compatible with the macOS dependencies. I `swift build --clean` is performed before they are fetched.",
                                                requiresValue:true,
                                                defaultValue:"false")
        static let imageName        = CliOption(keys:["-i", "--image-name", "DOCKER_IMAGE_NAME"],
                                                description:"The Docker image name to run the commands in. Defaults to saltzmanjoelh/swiftubuntu",
                                                requiresValue:true,
                                                defaultValue:"saltzmanjoelh/swiftubuntu")
    }
    public func handleFetchPackages(option:CliOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[FetchPackages.command.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "SOURCE_CODE_PATH was not provided.")
        }
        guard let forLinux = index[FetchPackages.linuxPackages.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "\(FetchPackages.linuxPackages.keys) keys were not provided.")
        }
        
        guard let imageName = index[FetchPackages.imageName.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "\(FetchPackages.imageName.keys) keys were not provided.")
        }
        try fetchPackages(at:sourcePath, forLinux:(forLinux as NSString).boolValue, inDockerImage: imageName)
    }
    
    // MARK: Build
    struct Build {
        static let command              = CliOption(keys: ["build"],
                                                    description: "Build a Swift package in Linux and have the build errors appear in Xcode.",
                                                    usage: "xchelper build SOURCE_CODE_PATH [OPTIONS]. SOURCE_CODE_PATH is the root of your package to call 'swift build' in.")
        static let buildConfiguration   = CliOption(keys:["-c", "--build-configuration", "BUILD_CONFIGURATION"],
                                                    description:"debug or release mode. Defaults to debug",
                                                    requiresValue:true,
                                                    defaultValue:"debug")
        static let imageName            = CliOption(keys:["-i", "--image-name", "DOCKER_IMAGE_NAME"],
                                                    description:"The Docker image name to run the commands in. Defaults to saltzmanjoelh/swiftubuntu",
                                                    requiresValue:true,
                                                    defaultValue:"saltzmanjoelh/swiftubuntu")
    }
    public func handleBuild(option:CliOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[Build.command.keys.first!]?.first else {
            throw XcodeHelperError.build(message: "SOURCE_CODE_PATH was not provided.")
        }
        guard let buildConfigurationString = index[Build.buildConfiguration.keys.first!]?.first else {
            throw XcodeHelperError.build(message: "\(Build.buildConfiguration.keys) not provided.")
        }
        let buildConfiguration = BuildConfiguration(from:buildConfigurationString)
        
        guard let imageName = index[Build.imageName.keys.first!]?.first else {
            throw XcodeHelperError.build(message: "\(Build.imageName.keys) not provided.")
        }
        try build(source: sourcePath, usingConfiguration: buildConfiguration, inDockerImage: imageName)
    }
    
    // MARK: Clean
    struct Clean {
        static let command              = CliOption(keys: ["clean"],
                                                    description: "Run swift build --clean on your package",
                                                    usage: "xchelper clean SOURCE_CODE_PATH [OPTIONS]. SOURCE_CODE_PATH is the root of your package to call 'swift build --clean' in.")
    }
    public func handleClean(option:CliOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[Clean.command.keys.first!]?.first else {
            throw XcodeHelperError.clean(message: "SOURCE_CODE_PATH was not provided.")
        }
        try clean(source: sourcePath)
    }
    // MARK: UpdateSymLinks
    struct UpdateSymLinks {
        static let command              = CliOption(keys: ["update-sym-links"],
                                                    description: "Restore the 'Dependency' sym links in Xcode after updating a package dependencies without having to generate a new Xcode project.",
                                                    usage: "xchelper updateSymLinks SOURCE_CODE_PATH [OPTIONS]. SOURCE_CODE_PATH is the root of your package to call 'swift build' in.")
    }
    public func handleUpdateSymLinks(option:CliOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[UpdateSymLinks.command.keys.first!]?.first else {
            throw XcodeHelperError.updateSymLinks(message: "SOURCE_CODE_PATH was not provided.")
        }
        try updateSymLinks(sourcePath: sourcePath)
    }
    // MARK: CreateArchive
    struct CreateArchive {
        static let command              = CliOption(keys: ["create-archive"],
                                                    description: "Archive files with tar.",
                                                    usage: "xchelper create-archive ARCHIVE_PATH FILES [OPTIONS]. ARCHIVE_PATH the full path and filename for the archive to be created. FILES is a space separated list of full paths to the files you want to archive.")
        static let buildConfiguration   = CliOption(keys:["-f", "--flat-list", "FLAT_LIST"],
                                                    description:"Put all the files in a flat list instead of maintaining directory structure",
                                                    requiresValue:true,
                                                    defaultValue:"true")
    }
    public func handleCreateArchive(option:CliOption) throws {
        let index = option.argumentIndex
        guard let paths = index[CreateArchive.command.keys.first!] else {
            throw XcodeHelperError.createArchive(message: "You didn't provide any paths.")
        }
        guard let archivePath = paths.first else {
            throw XcodeHelperError.createArchive(message: "You didn't provide the archive path.")
        }
        guard paths.count > 1 else {
            throw XcodeHelperError.createArchive(message: "You didn't provide any files to archive.")
        }
        let filePaths = Array(paths[1..<paths.count])
        try createArchive(at: archivePath, with: filePaths)
    }
    
    // MARK: UploadArchive
    struct UploadArchive {
        static let command              = CliOption(keys: ["upload-archive"],
                                                    description: "Upload an archive to S3",
                                                    requiresValue: true,
                                                    usage: "xchelper upload-archive ARCHIVE_PATH [OPTIONS]. ARCHIVE_PATH the path of the archive that you want to upload to S3.")
        static let bucket               = CliOption(keys:["-b", "--bucket", "S3_BUCKET"],
                                                    description:"The bucket that you want to upload your archive to.",
                                                    requiresValue:true)
        static let region               = CliOption(keys:["-r", "--region", "S3_REGION"],
                                                    description:"The bucket's region.",
                                                    requiresValue:true,
                                                    defaultValue:"us-east-1")
        static let key                  = CliOption(keys:["-k", "--key", "S3_KEY"],
                                                    description:"The S3 key for the bucket.",
                                                    requiresValue:true)
        static let secret               = CliOption(keys:["-s", "--secret", "S3_SECRET"],
                                                    description:"The secret for the key.",
                                                    requiresValue:true)
    }
    public func handleUploadArchive(option:CliOption) throws {
        let index = option.argumentIndex
        guard let archivePath = index[UploadArchive.command.keys.first!]?.first else {
            throw XcodeHelperError.uploadArchive(message: "You didn't prove the path to the archive that you want to upload.")
        }
        guard let bucket = index[UploadArchive.bucket.keys.first!]?.first else {
            throw XcodeHelperError.uploadArchive(message: "You didn't provide the S3 bucket to upload to.")
        }
        guard let region = index[UploadArchive.region.keys.first!]?.first else {
            throw XcodeHelperError.uploadArchive(message: "You didn't provide the region for the bucket.")
        }
        guard let key = index[UploadArchive.key.keys.first!]?.first else {
            throw XcodeHelperError.uploadArchive(message: "You didn't provide the key for the bucket.")
        }
        guard let secret = index[UploadArchive.secret.keys.first!]?.first else {
            throw XcodeHelperError.uploadArchive(message: "You didn't provide the secret for the key.")
        }
        try uploadArchive(at: archivePath, to: bucket, in: region, key: key, secret: secret)
    }
}
