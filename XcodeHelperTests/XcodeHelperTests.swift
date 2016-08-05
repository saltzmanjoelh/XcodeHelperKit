//
//  XcodeHelpersTests.swift
//  XcodeHelpersTests
//
//  Created by Joel Saltzman on 7/30/16.
//
//

import XCTest
import TaskExtension
import DockerTask
#if os(OSX) || os(iOS)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

@testable
import XcodeHelper

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
            Task.run(launchPath: "/bin/rm", arguments: ["-Rf", sourcePath!])
        }
    }
    //returns the temp dir that we cloned into
    private func cloneToTempDirectory(repoURL:String) -> String? {
        //use /tmp instead of FileManager.default.temporaryDirectory because Docker for mac specifies /tmp by default and not /var...
        let tempDir = "/tmp/\(UUID())/"
        let cloneResult = Task.run(launchPath: "/usr/bin/env", arguments: ["git", "clone", repoURL, tempDir], silenceOutput: false)
        XCTAssert(cloneResult.exitCode == 0, "Failed to clone repo: \(cloneResult.error)")
        XCTAssert(FileManager.default.fileExists(atPath: tempDir))
        print("done cloning temp dir: \(tempDir)")
        return tempDir
    }
    
    func testUpdateSymLinks() {
        sourcePath = cloneToTempDirectory(repoURL: executableRepoURL)
        let packages = ["Hello"]
        let helper = XcodeHelper()
        
        do {
            print("updating sym links at: \(sourcePath)")
            try helper.build(source: sourcePath!, usingConfiguration: .debug)
            try helper.updateSymLinks(sourcePath: sourcePath!)
        } catch let e {
            XCTFail("Error: \(e)")
        }
        
        for package in packages{
            let path = sourcePath!.appending("Packages/\(package)")
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), "Failed to find \(path)")
            XCTAssertTrue(isDirectory.boolValue, "\(path) was not a directory")
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
    
    
}
