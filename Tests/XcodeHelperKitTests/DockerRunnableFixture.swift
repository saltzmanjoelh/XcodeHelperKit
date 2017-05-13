//
//  DockerRunnableFixture.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 12/18/16.
//
//

import Foundation
import DockerProcess
import ProcessRunner

struct DockerRunnableFixture: DockerRunnable {
    init(){
        
    }
    public init(command: String, commandOptions: [String]?, imageName: String?, commandArgs: [String]?) {
        
    }

    //closure to return an expected result without actually doing anything on the filesystem
    var testLaunch:((Bool) -> ProcessResult)?
    @discardableResult
    public func launch(printOutput:Bool, outputPrefix: String?) -> ProcessResult {
        return (output: nil, error: nil, exitCode: -1)
    }
}
