//
//  BuildConfigurationTest.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 12/11/16.
//
//

import XCTest
@testable
import XcodeHelperKit

class BuildConfigurationTests: XCTestCase {
    func testbuildDirectory_withSuffix(){
        let path = "/tmp/"
        let configuration = BuildConfiguration.debug
        
        let buildDirectory = configuration.buildDirectory(inSourcePath: path)
        
        XCTAssertEqual(buildDirectory, "/tmp/.build/")
    }
    func testbuildDirectory_withoutSuffix(){
        let path = "/tmp"
        let configuration = BuildConfiguration.debug
        
        let buildDirectory = configuration.buildDirectory(inSourcePath: path)
        
        XCTAssertEqual(buildDirectory, "/tmp/.build/")
    }
    
    func testInit_release(){
        let configuration = BuildConfiguration.init(from: "release")
        
        XCTAssertEqual(configuration, BuildConfiguration.release)
    }
    func testInit_debug(){
        let configuration = BuildConfiguration.init(from: "debug")
        
        XCTAssertEqual(configuration, BuildConfiguration.debug)
    }
    func testAllValues() {
        let values = BuildConfiguration.allValues
        
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values.first, BuildConfiguration.debug)
        XCTAssertEqual(values.last, BuildConfiguration.release
        )
    }
    func testYamlPath_withoutSuffix(){
        let buildPath = "/tmp"
        let configuration = BuildConfiguration.debug
        
        let yamlPath = configuration.yamlPath(inSourcePath: buildPath)
        
        XCTAssertEqual(yamlPath, "/tmp/.build/\(configuration).yaml")
    }
    func testYamlPath_withSuffix(){
        let buildPath = "/tmp/"
        let configuration = BuildConfiguration.release
        
        let yamlPath = configuration.yamlPath(inSourcePath: buildPath)
        
        XCTAssertEqual(yamlPath, "/tmp/.build/\(configuration).yaml")
    }
}
