//
//  XcodeHelperKitTests.swift
//  XcodeHelperKitTests
//
//  Created by Joel Saltzman on 7/30/16.
//
//

import XCTest
import SynchronousTask
import DockerTask
#if os(OSX) || os(iOS)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

@testable
import XcodeHelperKit

class XcodeHelperKitTests: XCTestCase {
    
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
            Task.run(launchPath: "/bin/rm", arguments: ["-Rf", sourcePath!])
        }
    }
    //returns the temp dir that we cloned into
    private func cloneToTempDirectory(repoURL:String) -> String? {
        //use /tmp instead of FileManager.default.temporaryDirectory because Docker for mac specifies /tmp by default and not /var...
        let tempDir = FileManager.default.homeDirectoryForCurrentUser.path.appending("/Documents/XcodeHelperKitTests/\(UUID())")
        if !FileManager.default.fileExists(atPath: tempDir) {
            do {
                try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: false, attributes: nil)
            }catch _{
                
            }
        }
        let cloneResult = Task.run(launchPath: "/usr/bin/env", arguments: ["git", "clone", repoURL, tempDir], silenceOutput: false)
        XCTAssert(cloneResult.exitCode == 0, "Failed to clone repo: \(cloneResult.error)")
        XCTAssert(FileManager.default.fileExists(atPath: tempDir))
        print("done cloning temp dir: \(tempDir)")
        return tempDir
    }
    
    func testFetchPackages() {
        sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
        let helper = XcodeHelper()
        
        do {
            let fetchResult = try helper.fetchPackages(at: sourcePath!, forLinux: false, inDockerImage: nil)
            if let fetchError = fetchResult.error {
                XCTFail("Error: \(fetchError)")
            }
            XCTAssertNotNil(fetchResult.output)
            XCTAssertTrue(fetchResult.output!.contains("Resolved version"))
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    func testFetchPackagesInLinux() {
        sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
        let helper = XcodeHelper()
        
        do {
            let fetchResult = try helper.fetchPackages(at: sourcePath!, forLinux: true, inDockerImage: "saltzmanjoelh/swiftubuntu")
            if let fetchError = fetchResult.error {
                XCTFail("Error: \(fetchError)")
            }
            XCTAssertNotNil(fetchResult.output)
            XCTAssertTrue(fetchResult.output!.contains("Resolved version"), "Should have found \"Resolved version\" in output.")
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath!.appending("/Packages"), isDirectory: &isDirectory), "Failed to find Packages dir")
            XCTAssertTrue(isDirectory.boolValue, "Packages symlink is not a directory")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    
    func testUpdateSymLinks() {
        sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
        let packages = ["Hello"]
        let helper = XcodeHelper()
        
        do {
            print("updating sym links at: \(sourcePath)")
            let buildResult = try helper.build(source: sourcePath!, usingConfiguration: .debug)
            if let buildError = buildResult.error {
                XCTFail("Error: \(buildError)")
            }
            
            try helper.updateSymLinks(sourcePath: sourcePath!)
        } catch let e {
            XCTFail("Error: \(e)")
        }
        
        for package in packages{
            let path = sourcePath!.appending("/Packages/\(package)")
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), "Failed to find symlink: \(path)")
            XCTAssertTrue(isDirectory.boolValue, "Symlink was not a directory: \(path)")
        }
    }
    func testShouldClean(){
        //build it in macOS so we know that it needs to be cleaned
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        Task.run(launchPath: "/bin/bash", arguments: ["-c", "cd \(sourcePath!) && swift build"], silenceOutput: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: BuildConfiguration.debug.buildDirectory(inSourcePath: sourcePath!)), ".build directory not found after build in macOS")
        
        do{
            let ans = try XcodeHelper().shouldClean(sourcePath: sourcePath!, forConfiguration: .debug)
            
            XCTAssertTrue(ans, "shouldClean should have returned true")
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
        
        
    }
    
    func testCleanLinuxBuilds() {
        //build first so that we have something to clean
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        Task.run(launchPath: "/bin/bash", arguments: ["-c", "cd \(sourcePath!) && swift build"], silenceOutput: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: BuildConfiguration.debug.buildDirectory(inSourcePath: sourcePath!)), ".build directory not found after build in macOS")
        let helper = XcodeHelper()
        
        do {
            try helper.clean(sourcePath: sourcePath!)
            
            XCTAssertFalse(FileManager.default.fileExists(atPath: BuildConfiguration.debug.buildDirectory(inSourcePath: sourcePath!)), ".build directory should not found after cleaning")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
    
    func testArchiveFlatList(){
        let helper = XcodeHelper()
        sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
        let archivePath = "\(sourcePath!)/test.tar"
        
        do{
            try helper.create(archive:archivePath, files: ["\(sourcePath!)/Package.swift", "\(sourcePath!)/Sources/Hello.swift"], flatList: true)
            
            XCTAssertTrue(FileManager.default.fileExists(atPath: archivePath), "Failed to create the archive")
            let subPath = sourcePath!.appending("/\(UUID())")//untar into subdir and make sure that there are no subsubdirs
            Task.run(launchPath: "/bin/bash", arguments: ["-c", "mkdir -p \(subPath) && /usr/bin/tar -xvf \(archivePath) -C \(subPath)"])
        
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
            try helper.create(archive:archivePath, files: ["\(sourcePath!)/Package.swift", "\(sourcePath!)/Sources/Hello.swift"], flatList: false)
            
            XCTAssertTrue(FileManager.default.fileExists(atPath: archivePath), "Failed to create the archive")
            let subPath = sourcePath!.appending("/\(UUID())")//untar into subdir and make sure that there are no subsubdirs
            Task.run(launchPath: "/bin/bash", arguments: ["-c", "mkdir -p \(subPath) && /usr/bin/tar -xvf \(archivePath) -C \(subPath)"])
        
            let contents = try FileManager.default.contentsOfDirectory(atPath: subPath)
            XCTAssertEqual(contents.count, 1, "There should be a root tmp directory")
            //make sure the subPath contains the structure from the archive
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: subPath.appending(sourcePath!)).count, 2, "There should be one Package.swift file and a Sources directory")
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }

    func testUploadArchive(){
        do{
            let helper = XcodeHelper()
            sourcePath = cloneToTempDirectory(repoURL: libraryRepoURL)
            let archiveName = "test.tar"
            let archivePath = "\(sourcePath!)/\(archiveName)"
            try helper.create(archive:archivePath, files: ["\(sourcePath!)/Package.swift", "\(sourcePath!)/Sources/Hello.swift"], flatList: true)
            
            
            let destination = "s3://saltzman.test/test.tar"
            let uploadResult = try helper.upload(archive: archivePath, to: destination)
            
            if let error = uploadResult.error {
                XCTFail("Error: \(error)")
            }
            XCTAssertNotNil(uploadResult.output)
            XCTAssertTrue(uploadResult.output!.hasPrefix("upload:"))
            XCTAssertTrue(uploadResult.output!.hasSuffix(archiveName.appending("\n")), "Output should end with \(archiveName)")
            let lsResult = Task.run(launchPath: "/usr/local/bin/aws", arguments: ["s3", "ls", destination])
            if let lsError = lsResult.error {
                XCTFail("Error: \(lsError)")
            }
            
        } catch let e {
            XCTFail("Error: \(e)")
        }
    }
}
