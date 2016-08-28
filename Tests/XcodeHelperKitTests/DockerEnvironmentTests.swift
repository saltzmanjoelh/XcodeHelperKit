//
//  DockerEnvironment.swift
//  XcodeHelperKitTests
//
//  Created by Joel Saltzman on 7/30/16.
//
//

import XCTest
import SynchronousProcess
import DockerProcess
#if os(OSX) || os(iOS)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

@testable
import XcodeHelperKit

class DockerEnvironmentTests: XCTestCase {
    
    func testEnvironment(){
        do {
            let imageName = try DockerEnvironment().imageName()
            XCTAssertEqual(imageName, "saltzmanjoelh/swiftubuntu")
        }catch let error {
            XCTFail("\(error)")
        }
    }
    
}
