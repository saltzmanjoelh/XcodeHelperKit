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
import ProcessRunner

let emptyProcessResult = ProcessResult(output:nil, error:nil, exitCode:0)

struct ProcessRunnableFixture: ProcessRunnable {

    public static var instanceTests = [((String, [String]?, [String:String]?, ((FileHandle) -> Void)?, ((FileHandle) -> Void)?) -> (String?, String?, Int32))]()
    @discardableResult
    static func synchronousRun(_ launchPath: String, arguments: [String]?, printOutput: Bool, outputPrefix: String?, environment: [String:String]?) -> ProcessResult {
        return createInstance(launchPath, arguments: arguments, printOutput: printOutput, outputPrefix: outputPrefix)
            .run(printOutput, outputPrefix: outputPrefix)
    }
    
    public static func createInstance(_ launchPath: String, arguments: [String]?, printOutput: Bool, outputPrefix: String?) -> ProcessRunnableFixture {
        let prefix =  outputPrefix != nil ? "\(outputPrefix!): " : ""
        let output = { (handle: FileHandle) in
            if !printOutput { return }
            print("\(prefix)\(String.init(data: handle.availableData, encoding: .utf8)!)")
        }
        var instance = try! ProcessRunnableFixture.init(launchPath: launchPath,
                                                        arguments: arguments,
                                                        environment: nil,
                                                        stdOut: output,
                                                        stdErr: output)
        if let test = ProcessRunnableFixture.instanceTests.first {
            instance.testRun = test
            _ = ProcessRunnableFixture.instanceTests.remove(at: 0)
        }
        return instance
    }
    
    
    
    var launchPath: String
    var arguments: [String]?
    
    init(launchPath: String, arguments: [String]?, environment: [String:String]?, stdOut: ((_ stdOutRead: FileHandle) -> Void)? = nil, stdErr: ((_ stdErrRead: FileHandle) -> Void)? = nil) throws {
        self.launchPath = launchPath
        self.arguments = arguments
    }
    
    //closure to return an expected result without actually doing anything on the filesystem
    var testRun:((String, [String]?, [String:String]?, ((FileHandle) -> Void)?, ((FileHandle) -> Void)?) -> (ProcessResult))?
    @discardableResult
    public func run(_ printOutput: Bool, outputPrefix: String?) -> ProcessResult {
        if let run = testRun {
            let prefix =  outputPrefix != nil ? "\(outputPrefix!): " : ""
            let output = { (handle: FileHandle) in
                if !printOutput { return }
                print("\(prefix)\(String.init(data: handle.availableData, encoding: .utf8)!)")
            }
            return run(launchPath, arguments, nil, output, output)
        }
        return emptyProcessResult
    }

    

}
