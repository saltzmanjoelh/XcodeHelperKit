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

class GitTagComponentTests: XCTestCase {
    func testGitTagComponentInit_major(){
        XCTAssertEqual(GitTagComponent.init(stringValue: "major"), GitTagComponent.major)
    }
    func testGitTagComponentInit_minor(){
        XCTAssertEqual(GitTagComponent.init(stringValue: "minor"), GitTagComponent.minor)
    }
    func testGitTagComponentInit_patch(){
        XCTAssertEqual(GitTagComponent.init(stringValue: "patch"), GitTagComponent.patch)
    }
    func testGitTagComponentInit_invalid(){
        XCTAssertNil(GitTagComponent.init(stringValue: "error"))
    }
}
