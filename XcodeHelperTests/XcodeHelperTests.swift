//
//  LinuxRunnersTests.swift
//  LinuxRunnersTests
//
//  Created by Joel Saltzman on 7/30/16.
//
//

import XCTest
import TaskExtension
import DockerTask

@testable
import LinuxRunner

class LinuxRunnersTests: XCTestCase {
    
    var sourcePath : String?
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        sourcePath = cloneToTempDirectory()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        if sourcePath != nil {
            Task.run(launchPath: "/bin/rm", arguments: ["-Rf", sourcePath!])
        }
    }
    //returns the temp dir that we cloned into
    private func cloneToTempDirectory() -> String? {
        //use /tmp instead of FileManager.default.temporaryDirectory because Docker for mac specifies /tmp by default and not /var...
        let tempDir = "/tmp/\(UUID())/"
        let cloneResult = Task.run(launchPath: "/usr/bin/env", arguments: ["git", "clone", "https://github.com/saltzmanjoelh/LinuxRunner.git", tempDir], silenceOutput: false)
        XCTAssert(cloneResult.exitCode == 0, "Failed to clone repo: \(cloneResult.error)")
        XCTAssert(FileManager.default.fileExists(atPath: tempDir))
        print("done cloning temp dir: \(tempDir)")
        return tempDir
    }
    
    func testUpdateSymLinks() {
        let packages = ["TaskExtension", "DockerTask"]
        let runner = LinuxRunner()
        
        do {
            print("updating sym links at: \(sourcePath)")
            try runner.build(source: sourcePath!, usingConfiguration: .debug)
            try runner.updateSymLinks(sourcePath: sourcePath!)
        }catch let e {
            XCTFail("Error: \(e)")
        }
        
        for package in packages{
            let path = sourcePath!.appending("Packages/\(package)")
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), "Failed to find \(path)")
            XCTAssertTrue(isDirectory, "\(path) was not a directory")
        }
    }
    
    func testCleanLinuxBuilds() {
        //run DockTask with new repo and build in both debug and release, verify .build dir, cleanLinuxBuild
//
//        let helper = LinuxRunner()
//        for subPath in helper.buildSubPaths {
//            guard let prefix = subPath.range(of: "/")?.lowerBound, let suffix = subPath.range(of: ".yaml")?.lowerBound else {
//                XCTFail("Failed to parse LinuxRunner.buildSubPath configurations")
//                return
//            }
//            let range = subPath.index(after:prefix)..<subPath.index(before:suffix)
//            let configuration = subPath.substring(with: range)
//            DockerTask.init(command: "run", commandOptions: ["--rm", "-v", "\(tempDir):\(tempDir)"], imageName: "saltzmanjoelh/swiftubuntu", commandArgs: ["/bin/bash", "-c", "swift build -c \(configuration)"]).launch()
//            XCTAssert(FileManager)
//        }
    }
    
    
}
