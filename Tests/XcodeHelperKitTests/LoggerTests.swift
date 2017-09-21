//
//  LoggerTests.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 6/3/17.
//
//

import XCTest
@testable import XcodeHelperKit

class LoggerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testLog() {
        let logger = Logger()
//        logger.log("one", forAction: "testLog")
        logger.log("one", for: .dockerBuild)
        //RunLoop.current.run(until: Date.init(timeIntervalSinceNow: 2))
    }

}
