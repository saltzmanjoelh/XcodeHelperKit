//
//  XcodeHelperCli.swift
//  XcodeHelper
//
//  Created by Joel Saltzman on 8/28/16.
//
//

import Foundation
import CliRunnable


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
            var fetchPackages = FetchPackagesOption.command
            fetchPackages.optionalArguments = [FetchPackagesOption.linuxPackages, FetchPackagesOption.imageName]
            fetchPackages.action = handleFetchPackages
            
            
            return [CliOptionGroup(description:"Commands:",
                                   options:[fetchPackages])]
        }
    }
    // MARK: FetchPackages
    struct FetchPackagesOption {
        static let command          = CliOption(keys: ["fetch-packages"],
                                                description: "Fetch the package dependencies via 'swift package fetch'",
                                                usage: "xchelper fetch-packages SOURCE_CODE_PATH [OPTIONS]. SOURCE_CODE_PATH is the root of your package to call 'swift package fetch' in.")
        static let linuxPackages    = CliOption(keys:["-l", "--linux-packages"],
                                                description:"Fetch the Linux version of the packages. Some packages have Linux specific dependencies. Some Linux dependencies are not compatible with the macOS dependencies. I `swift build --clean` is performed before they are fetched. Default is false",
                                                requiresValue:true,
                                                defaultValue:"false")
        static let imageName        = CliOption(keys:["-i", "--image-name"],
                                                description:"The Docker image name to run the commands in. Defaults to saltzmanjoelh/swiftubuntu",
                                                requiresValue:true,
                                                defaultValue:"saltzmanjoelh/swiftubuntu")
    }
    public func handleFetchPackages(option:CliOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[FetchPackagesOption.command.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "SOURCE_CODE_PATH was not provided.")
        }
        guard let forLinux = index[FetchPackagesOption.linuxPackages.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "\(FetchPackagesOption.linuxPackages.keys) keys were not provided.")
        }
        
        guard let imageName = index[FetchPackagesOption.imageName.keys.first!]?.first else {
            throw XcodeHelperError.fetch(message: "\(FetchPackagesOption.imageName.keys) keys were not provided.")
        }
        try fetchPackages(at:sourcePath, forLinux:(forLinux as NSString).boolValue, inDockerImage: imageName)
    }
    
    // MARK: Build
    struct BuildOption {
        static let command              = CliOption(keys: ["build"],
                                                    description: "Build a Swift package in Linux and have the build errors appear in Xcode.",
                                                    usage: "xchelper build SOURCE_CODE_PATH [OPTIONS]. SOURCE_CODE_PATH is the root of your package to call 'swift build' in.")
        static let buildConfiguration   = CliOption(keys:["-c", "--build-configuration"],
                                                    description:"debug or release mode. Defaults to debug",
                                                    requiresValue:true,
                                                    defaultValue:"debug")
        static let imageName            = CliOption(keys:["-i", "--image-name"],
                                                    description:"The Docker image name to run the commands in. Defaults to saltzmanjoelh/swiftubuntu",
                                                    requiresValue:true,
                                                    defaultValue:"saltzmanjoelh/swiftubuntu")
    }
    public func handleBuild(option:CliOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[BuildOption.command.keys.first!]?.first else {
            throw XcodeHelperError.build(message: "SOURCE_CODE_PATH was not provided.")
        }
        guard let buildConfigurationString = index[BuildOption.buildConfiguration.keys.first!]?.first else {
            throw XcodeHelperError.build(message: "\(BuildOption.buildConfiguration.keys) not provided.")
        }
        let buildConfiguration = BuildConfiguration(from:buildConfigurationString)
        
        guard let imageName = index[BuildOption.imageName.keys.first!]?.first else {
            throw XcodeHelperError.build(message: "\(BuildOption.imageName.keys) not provided.")
        }
        try build(source: sourcePath, usingConfiguration: buildConfiguration, inDockerImage: imageName)
    }
    
    // MARK: Clean
    struct CleanOption {
        static let command              = CliOption(keys: ["clean"],
                                                    description: "Run swift build --clean on your package",
                                                    usage: "xchelper clean SOURCE_CODE_PATH [OPTIONS]. SOURCE_CODE_PATH is the root of your package to call 'swift build --clean' in.")
    }
    public func handleClean(option:CliOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[BuildOption.command.keys.first!]?.first else {
            throw XcodeHelperError.clean(message: "SOURCE_CODE_PATH was not provided.")
        }
        try clean(source: sourcePath)
    }
    // MARK: UpdateSymLinks
    struct UpdateSymLinksOption {
        static let command              = CliOption(keys: ["update-sym-links"],
                                                    description: "Restore the 'Dependency' sym links in Xcode after updating a package dependencies without having to generate a new Xcode project.",
                                                    usage: "xchelper updateSymLinks SOURCE_CODE_PATH [OPTIONS]. SOURCE_CODE_PATH is the root of your package to call 'swift build' in.")
    }
    public func handleUpdateSymLinks(option:CliOption) throws {
        let index = option.argumentIndex
        guard let sourcePath = index[BuildOption.command.keys.first!]?.first else {
            throw XcodeHelperError.updateSymLinks(message: "SOURCE_CODE_PATH was not provided.")
        }
        try updateSymLinks(sourcePath: sourcePath)
    }
    // MARK: Archive
    struct ArchiveOption {
        static let command              = CliOption(keys: ["create-archive"],
                                                    description: "Archive files with tar.",
                                                    usage: "xchelper create-archive DESTINATION_PATH FILES [OPTIONS]. DESTINATION_PATH the full path and filename for the archive to be create. FILES is a space separated list of full paths to the files you want to archive.")
        static let buildConfiguration   = CliOption(keys:["-f", "--flat-list"],
                                                    description:"Put all the files in a flat list instead of maintaining directory structure",
                                                    requiresValue:true,
                                                    defaultValue:"true")
    }
    public func handleArchive(option:CliOption) throws {
        let index = option.argumentIndex
        guard let paths = index[BuildOption.command.keys.first!] else {
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
}
