//
//  XcodeHelperTests.swift
//  XcodeHelperKitTests
//
//  Created by Joel Saltzman on 7/30/16.
//
//

import XCTest
import ProcessRunner
import DockerProcess
import S3Kit

//#if os(OSX) || os(iOS)
    import Darwin
//#elseif os(Linux)
//    import Glibc
//#endif

@testable
import XcodeHelperKit

enum LibraryTag: Int {
    case major = 1
    case minor = 0
    case patch = 3
}

let testPackageName = "Hello"
let testVersionedPackageName = "Hello.git-918358885156091396"

class XcodeHelperTests: XCTestCase {
    
//    just create a sample repo that uses another repo so that we don't have to worry about swift version breakage
    let executableRepoURL = "https://github.com/saltzmanjoelh/HelloSwift" //we use a different repo for testing because this repo isn't meant for linux
    let libraryRepoURL = "https://github.com/saltzmanjoelh/Hello"
    var sourcePath : String?
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        if sourcePath != nil {
            ProcessRunner.synchronousRun("/bin/rm", arguments: ["-Rf", sourcePath!])
        }
    }
    //returns the temp dir that we cloned into
    private func cloneToTempDirectory(repoURL:String) -> String? {
        //use /tmp instead of FileManager.default.temporaryDirectory because Docker for mac specifies /tmp by default and not /var...
//        guard let tempDir = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path.appending("/XcodeHelperKitTests/\(UUID())") else{
//            XCTFail("Failed to get user dir")
//            return nil
//        }
        let tempDir = "/tmp/\(UUID())"
        if !FileManager.default.fileExists(atPath: tempDir) {
            do {
                try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: false, attributes: nil)
            }catch _{
                
            }
        }
        let cloneResult = ProcessRunner.synchronousRun("/usr/bin/env", arguments: ["git", "clone", repoURL, tempDir], printOutput: true)
        XCTAssert(cloneResult.exitCode == 0, "Failed to clone repo: \(String(describing: cloneResult.error))")
        XCTAssert(FileManager.default.fileExists(atPath: tempDir))
        print("done cloning temp dir: \(tempDir)")
        return tempDir
    }
    func testXcodeHelperErrors(){
        let errors: [XcodeHelperError] = [.clean(message: "clean"),
                                          .updatePackages(message: "update"),
                                          .symlinkDependencies(message: "symlinkDependencies"),
                                          .createArchive(message: "createArchive"),
                                          .uploadArchive(message: "uploadArchive"),
                                          .gitTagParse(message: "gitTagParse"),
                                          .gitTag(message: "gitTag"),
                                          .createXcarchive(message: "createXcarchive"),
                                          .xcarchivePlist(message: "xcarchivePlist"),
                                          .unknownOption(message: "unknownOption")]
        for error in errors{
            XCTAssertEqual(error.description, "\(error)")
        }
    }
    func testXcodeHelperError_build(){
        let err = XcodeHelperError.dockerBuild(message: "build", exitCode: 111)
        
        XCTAssertEqual(err.description, "build")
        if case XcodeHelperError.dockerBuild(let buildError) = err {
            XCTAssertEqual(buildError.exitCode, 111)
        }else{
            XCTFail("Failed to parse build error")
        }
    }
    
    func testInit(){
        XCTAssertNotNil(XcodeHelper(dockerRunnable: DockerRunnableFixture.self))
    }
    func testUpdateDockerPackages(){
        guard FileManager.default.fileExists(atPath: "/usr/local/bin/docker") else { return }
        do{
            sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
            let helper = XcodeHelper(dockerRunnable: DockerProcess.self, processRunnable: ProcessRunnableFixture.self)
            ProcessRunnableFixture.instanceTests.append({ (launchPath: String, arguments: [String]?, env: [String : String]?, stdout:((FileHandle) -> Void)?, stdErr:((FileHandle) -> Void)?) -> ProcessResult in
                var exitCode: Int32 = 0
                if let args = arguments,
                    args.contains("swift package update") {
                }else{
                    print("Invalid args")
                    exitCode = 1
                }
                return ProcessResult(output:"done", error:nil, exitCode:exitCode)
            })
            let result = try helper.updateDockerPackages(at: sourcePath!, inImage: "swift", withVolume: "testing")
            
            XCTAssertNil(result.error)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertNotNil(result.output)
        }catch let e{
            XCTFail("\(e)")
        }
    }
    //We aren't moving packages around any more. We use volumes for each platform
    /*func testUpdateDockerPackages_backupPackages(){
        guard FileManager.default.fileExists(atPath: "/usr/local/bin/docker") else { return }
        do{
            sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
            let helper = XcodeHelper(dockerRunnable: DockerProcess.self, processRunnable: ProcessRunnableFixture.self)
            var didBackupPackages = false
            ProcessRunnableFixture.instanceTests.append({ (launchPath: String, arguments: [String]?, env: [String : String]?, stdout:((FileHandle) -> Void)?, stdErr:((FileHandle) -> Void)?) -> ProcessResult in
                if launchPath.hasSuffix("mv"), let lastArg = arguments?.last, lastArg.hasSuffix("backup") {
                    didBackupPackages = true
                }
                return emptyProcessResult
            })
            _ = try helper.updateDockerPackages(at: sourcePath!, inImage: "swift", withVolume: "testing")
            
            XCTAssertTrue(didBackupPackages)
        }catch let e{
            XCTFail("\(e)")
        }
    }
    func testUpdateDockerPackages_restorePackages(){
        guard FileManager.default.fileExists(atPath: "/usr/local/bin/docker") else { return }
        do{
            sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
            let helper = XcodeHelper(dockerRunnable: DockerProcess.self, processRunnable: ProcessRunnableFixture.self)
            //backup
            ProcessRunnableFixture.instanceTests.append({ _, _, _, _, _ in
                return emptyProcessResult
            })
            //restore
            var didRestorePackages = false
            ProcessRunnableFixture.instanceTests.append({ (launchPath: String, arguments: [String]?, env: [String : String]?, stdout:((FileHandle) -> Void)?, stdErr:((FileHandle) -> Void)?) -> ProcessResult in
                if launchPath.hasSuffix("mv"), let lastArg = arguments?.last, lastArg.hasSuffix("repositories") {
                    didRestorePackages = true
                }
                return emptyProcessResult
            })
            _ = try helper.updateDockerPackages(at: sourcePath!, inImage: "swift", withVolume: "testing")
            
            XCTAssertTrue(didRestorePackages)
        }catch let e{
            XCTFail("\(e)")
        }
    }*/
    
//    func testUpdateMacOsPackages() {
//        
//    }
//    
//    func testSymlinkDependencies() {
//        
//    }
    
    func testProjectFilePath() {
        do {
            sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
            _ = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath!) && /usr/bin/swift package generate-xcodeproj"])
            let helper = XcodeHelper()
            
            let path = try helper.projectFilePath(for: sourcePath!)
            
            XCTAssert(path.contains("/HelloSwift.xcodeproj/project.pbxproj"))
        } catch let e {
            XCTFail("Error: \(e)")
        }
        
    }
    
    func testPackageNames(){
        do{
            sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
            _ = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath!) && /usr/bin/swift package generate-xcodeproj"])
            let helper = XcodeHelper()
            
            let packageNames = try helper.packageNames(from: sourcePath!)
            
            XCTAssertEqual(packageNames.count, 1)//one for package directory
            XCTAssertEqual(packageNames.last, testVersionedPackageName)
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    
    func testGenerateXcodeProject(){
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        let helper = XcodeHelper()
        
        do {
            let result = try helper.generateXcodeProject(at: sourcePath!)
            
            XCTAssertNil(result.error, result.error!)
            XCTAssertNotNil(result.output!)
            XCTAssertEqual(result.output!, "generated: ./Hello.xcodeproj\n")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    
    func testSymlinkDependencyPath(){
        do{
            sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
            _ = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath!) && /usr/bin/swift package generate-xcodeproj"])
            let packages = [testPackageName]
            let helper = XcodeHelper()
            let packagesURL = helper.packagesURL(at: sourcePath!)
            let packageName = try helper.packageNames(from: sourcePath!).last
            let dependencyURL = packagesURL.appendingPathComponent(packageName!)
            
            let result = try helper.symlink(dependencyPath: dependencyURL.path)
            
            XCTAssertNotNil(result)
            XCTAssertEqual(result, packages[0])
            let symlink = packagesURL.appendingPathComponent(result!).path
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: symlink)
            XCTAssertEqual(destination, dependencyURL.path)
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    
    func testUpdateXcodeReferences() {
        do {
            sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
            _ = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath!) && /usr/bin/swift package generate-xcodeproj"])
            let helper = XcodeHelper()
            let url = URL.init(fileURLWithPath: sourcePath!)
                .appendingPathComponent(".build")
                .appendingPathComponent("checkouts")
                .appendingPathComponent(testVersionedPackageName)
            
            try helper.updateXcodeReferences(for: url, at: sourcePath!, using: testPackageName)
            
            let projectPath = try helper.projectFilePath(for: sourcePath!)
            let file = try String(contentsOfFile: projectPath)
            XCTAssertFalse(file.contains(testVersionedPackageName), "Xcode project should not contain any package versions")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testShouldClean(){
        //build it in macOS so we know that it needs to be cleaned
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath!) && swift build"], printOutput: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: BuildConfiguration.debug.buildDirectory(inSourcePath: sourcePath!)), ".build directory not found after building in macOS")
        
        do{
            let ans = try XcodeHelper().shouldClean(sourcePath: sourcePath!, using: .debug)
            
            XCTAssertTrue(ans, "shouldClean should have returned true")
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
        
        
    }
    
    func testBuildInDocker(){
        guard FileManager.default.fileExists(atPath: "/usr/local/bin/docker") else { return }
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        let helper = XcodeHelper()
        
        do {
            let result = try helper.dockerBuild(sourcePath!, with: [.removeWhenDone], using: .debug, in: "swift", persistentVolumeName: "platform")
            
            XCTAssertNil(result.error, result.error!)
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testPersistentVolumeOptions(){
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        let helper = XcodeHelper()
        let subdirectoryName = "platform"
        // source/.build/platform/
        let subdirectoryURL = URL(fileURLWithPath: sourcePath!).appendingPathComponent(".build", isDirectory: true)
                                    .appendingPathComponent(subdirectoryName, isDirectory: true)
        do {
            let dockerRunOptions = try helper.persistentVolumeOptions(at: sourcePath!, using: subdirectoryName)
            
            //first one should contain .build
            //not persisting Packages directory for now since it causes swift compiler to crash
            let directories = [".build"]//, "Packages"
            XCTAssertEqual(dockerRunOptions.count, directories.count)
            for index in 0..<directories.count {
                switch dockerRunOptions[index] {
                case .volume(let source, let destination):
                    XCTAssertEqual(source, subdirectoryURL.appendingPathComponent(directories[index]).path)// source/.build/platform/.build
                    XCTAssertEqual(destination, subdirectoryURL.deletingLastPathComponent()// source/.build
                                                .deletingLastPathComponent()
                                                .appendingPathComponent(directories[index])
                                                .path)
                    
                    XCTAssertTrue(FileManager.default.fileExists(atPath: source))
                default:
                    XCTFail("volume option should have been returned")
                }
            }
        }catch let e{
            XCTFail("Error: \(e)")
        }
    }
    func testPersistentVolume() {
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        let helper = XcodeHelper()
        let volumeName = "platform"
        let subdirectoryURL = URL(fileURLWithPath: sourcePath!)         // source
            .appendingPathComponent(".build", isDirectory: true)        // source/.build
            .appendingPathComponent(volumeName, isDirectory: true)// source/.build/platform
        let subdirectoryName = ".build"
        do {
            let dockerRunOption = try helper.persistentVolume(subdirectoryName, in: subdirectoryURL)
            
            switch dockerRunOption {
            case .volume(let source, let destination):
                // source/.build/platform/Packages
                XCTAssertEqual(source, subdirectoryURL.appendingPathComponent(subdirectoryName).path)
                // source/.build/platform/../../Packages
                XCTAssertEqual(destination, subdirectoryURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(subdirectoryName, isDirectory: true).path)
                
                XCTAssertTrue(FileManager.default.fileExists(atPath: source))
            default:
                XCTFail("volume option should have been returned")
            }
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    
    func testArchiveFlatList(){
        let helper = XcodeHelper()
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        let archivePath = "\(sourcePath!)/test.tar"
        
        do{
            try helper.createArchive(at:archivePath, with: ["\(sourcePath!)/Package.swift", "\(sourcePath!)/Sources/Hello.swift"], flatList: true)
            
            XCTAssertTrue(FileManager.default.fileExists(atPath: archivePath), "Failed to create the archive")
            let subPath = sourcePath!.appending("/\(UUID())")//untar into subdir and make sure that there are no subsubdirs
            ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "mkdir -p \(subPath) && /usr/bin/tar -xvf \(archivePath) -C \(subPath)"])
        
            let contents = try FileManager.default.contentsOfDirectory(atPath: subPath)
            XCTAssertEqual(contents.count, 2, "There should be exactly 2 files")
            XCTAssertFalse("\(contents)".contains("tmp"), "Flat list archiving shouldn't contain a directory structure")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testStructuredArchive(){
        let helper = XcodeHelper()
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        let archivePath = "\(sourcePath!)/test.tar"
        
        do{
            try helper.createArchive(at:archivePath, with: ["\(sourcePath!)/Package.swift", "\(sourcePath!)/Sources/Hello.swift"], flatList: false)
            
            XCTAssertTrue(FileManager.default.fileExists(atPath: archivePath), "Failed to create the archive")
            let subPath = sourcePath!.appending("/\(UUID())")//untar into subdir and make sure that there are no subsubdirs
            ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "mkdir -p \(subPath) && /usr/bin/tar -xvf \(archivePath) -C \(subPath)"])
        
            let contents = try FileManager.default.contentsOfDirectory(atPath: subPath)
            XCTAssertEqual(contents.count, 1, "There should be a root tmp directory")
            //make sure the subPath contains the structure from the archive
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: subPath.appending(sourcePath!)).count, 2, "There should be one Package.swift file and a Sources directory")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }

    func testUploadArchive(){
        guard ProcessInfo.processInfo.environment["TRAVIS_OS_NAME"] == nil else { return }
        do{
            let bucket = "saltzman.test"
            let region = "us-east-1"
            let helper = XcodeHelper()
            sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
            let archiveName = "test.zip"
            let archivePath = "\(sourcePath!)/\(archiveName)"
            try helper.createArchive(at:archivePath, with: ["\(sourcePath!)/Package.swift", "\(sourcePath!)/Sources/Hello.swift"], flatList: true)
            
            if FileManager.default.fileExists(atPath: "/Users/\(ProcessInfo.processInfo.environment["LOGNAME"]!)/Projects/XcodeHelper/XcodeHelperKit/s3Credentials.csv") {
                try helper.uploadArchive(at: archivePath, to: bucket, in: region, using:"/Users/\(ProcessInfo.processInfo.environment["LOGNAME"]!)/Projects/XcodeHelper/XcodeHelperKit/s3Credentials.csv")
            }else{
                let key = ProcessInfo.processInfo.environment["KEY"]!
                let secret = ProcessInfo.processInfo.environment["SECRET"]!
                try helper.uploadArchive(at: archivePath, to: bucket, in: region, key: key, secret: secret)
            }
            
            
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
        
    }
    
    func testGetGitTag() {
        do {
            let helper = XcodeHelper()
            sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
            
            let tag = try helper.getGitTag(at:sourcePath!)
            
            XCTAssertEqual(tag, "\(LibraryTag.major.rawValue).\(LibraryTag.minor.rawValue).\(LibraryTag.patch.rawValue)")
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testGitTagTuple() {
        let helper = XcodeHelper()
        
        let tag = helper.gitTagTuple("1.2.3")
        
        XCTAssertNotNil(tag)
        XCTAssert(tag!.0 == 1)
        XCTAssert(tag!.1 == 2)
        XCTAssert(tag!.2 == 3)
    }
    func testGitTagTuple_InvalidFormat() {
        let helper = XcodeHelper()
        
        let tag = helper.gitTagTuple("0.0")
        
        XCTAssertNil(tag)
    }
    func testLargestGitTag_Major() {
        do {
            let helper = XcodeHelper()
            
            let tag = try helper.largestGitTag(tagStrings: ["1000.1.1", "999.1.1", "1.1000.1", "1.1.1000"])
            
            XCTAssertEqual(tag, "1000.1.1")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testLargestGitTag_Minor() {
        do {
            let helper = XcodeHelper()
            
            let tag = try helper.largestGitTag(tagStrings: ["1.1.1", "1.1000.1", "1.999.1", "1.1.1000"])
            
            XCTAssertEqual(tag, "1.1000.1")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testLargestGitTag_Patch() {
        do {
            let helper = XcodeHelper()
            
            let tag = try helper.largestGitTag(tagStrings: ["1.1.1", "1.1000.1", "1.1000.1000"])
            
            XCTAssertEqual(tag, "1.1000.1000")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    
    
    func testIncrementGitTagMajor() {
        do {
            let helper = XcodeHelper()
            sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
            let expectedValue = "\(LibraryTag.major.rawValue+1).0.0"
            
            let value = try helper.incrementGitTag(component: GitTagComponent.major, at: sourcePath!)
            
            XCTAssertEqual(value, expectedValue)
            let updatedTag = try helper.getGitTag(at:sourcePath!)
            XCTAssertEqual(updatedTag, expectedValue)
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testIncrementGitTagMinor() {
        do {
            let helper = XcodeHelper()
            sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
            let expectedValue = "\(LibraryTag.major.rawValue).\(LibraryTag.minor.rawValue+1).0"
            
            let value = try helper.incrementGitTag(component: GitTagComponent.minor, at: sourcePath!)
            
            XCTAssertEqual(value, expectedValue)
            let updatedTag = try helper.getGitTag(at:sourcePath!)
            XCTAssertEqual(updatedTag, expectedValue)
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testIncrementGitTagPatch() {
        do {
            let helper = XcodeHelper()
            sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
            let expectedValue = "\(LibraryTag.major.rawValue).\(LibraryTag.minor.rawValue).\(LibraryTag.patch.rawValue+1)"
            
            let value = try helper.incrementGitTag(component: GitTagComponent.patch, at: sourcePath!)
            
            XCTAssertEqual(value, value)
            let updatedTag = try helper.getGitTag(at:sourcePath!)
            XCTAssertEqual(updatedTag, expectedValue)
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testPushGitTagFailure() {
        do{
            let helper = XcodeHelper()
            sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
            
            try helper.pushGitTag(tag:"99.99.99", at: sourcePath!)
            
        } catch _ {
            return
        }
        XCTFail("Pushing an invalid tag should have thrown an error")
    }
    func testPushGitTag() {
        guard ProcessInfo.processInfo.environment["TRAVIS_OS_NAME"] == nil else { return }
        let helper = XcodeHelper()
        //get the current tag
        var tag: String?
        do {
            sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
            tag = try helper.incrementGitTag(component: GitTagComponent.patch, at: sourcePath!)
        } catch let e {
            XCTFail("Error: \(e)")
        }
        defer { //cleanup
            let result = ProcessRunner.synchronousRun("/bin/bash", arguments: ["-c", "cd \(sourcePath!) && /usr/bin/git tag --delete \(tag!) && /usr/bin/git push origin :refs/tags/\(tag!)"])
            if result.exitCode != 0, let error = result.error {
                XCTFail("Error deleting git tag: \(error)")
            }
        }
        
        do{
            try helper.pushGitTag(tag:tag!, at: sourcePath!)
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    
    func testCreateXcarchive() {
        
        do{
            let path = "/tmp"
            let appName = "TestApp"
            let schemeName = "TestAppScheme"
            let plist = "Info.plist"
            let binaryPath = "/tmp/\(appName)"
            FileManager.default.createFile(atPath: binaryPath, contents: "Hi".data(using: String.Encoding.utf8), attributes: nil)
            let helper = XcodeHelper()
            
            let processResult = try helper.createXcarchive(in: path, with: binaryPath, from: schemeName)
            let archivePath = processResult.output?.components(separatedBy: "\n").last
            
            XCTAssertNotNil(archivePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: archivePath!))
            XCTAssertTrue(FileManager.default.fileExists(atPath: "\(archivePath!)/\(plist)"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: "\(archivePath!)/Products/\(appName).tar"))
            try! FileManager.default.removeItem(atPath: URL(fileURLWithPath: archivePath!).deletingLastPathComponent().path)
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
        
    }
    
}
