//
//  ProcessRunnableFixture.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 1/7/17.
//
//

import Foundation

import Foundation
import DockerProcess
import SynchronousProcess

let emptyProcessResult = ProcessResult(output:nil, error:nil, exitCode:0)

struct ProcessRunnableFixture: ProcessRunnable {
    
    public static var instanceTests = [(String, [String]?, Bool, String?) -> ProcessResult]()
    
    var launchPath: String
    var arguments: [String]?
    
    init(_ launchPath: String, arguments: [String]?, printOutput: Bool, outputPrefix: String?){
        self.launchPath = launchPath
        self.arguments = arguments
    }
    
    public static func createInstance(_ launchPath: String, arguments: [String]?, printOutput: Bool, outputPrefix: String?) -> ProcessRunnableFixture {
        var instance = ProcessRunnableFixture(launchPath, arguments: arguments, printOutput: printOutput, outputPrefix: outputPrefix)
        if let test = ProcessRunnableFixture.instanceTests.first {
            instance.testRun = test
            _ = ProcessRunnableFixture.instanceTests.remove(at: 0)
        }
        return instance
    }
    
    @discardableResult
    public static func run(_ launchPath: String, arguments: [String]?, printOutput: Bool, outputPrefix: String?) -> ProcessResult {
        return createInstance(launchPath, arguments: arguments, printOutput: printOutput, outputPrefix: outputPrefix).run(printOutput, outputPrefix: outputPrefix)
    }

    
    //closure to return an expected result without actually doing anything on the filesystem
    var testRun:((String, [String]?, Bool, String?) -> ProcessResult)?
    @discardableResult
    public func run(_ printOutput: Bool, outputPrefix: String?) -> ProcessResult {
        if let run = testRun {
            return run(launchPath, arguments, printOutput, outputPrefix)
        }
        return emptyProcessResult
    }

    

}
