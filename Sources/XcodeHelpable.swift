//
//  XcodeHelpable.swift
//  XcodeHelperKit
//
//  Created by Joel Saltzman on 11/26/16.
//
//

import Foundation
import SynchronousProcess

public protocol XcodeHelpable {
    
    //    @discardableResult func fetchPackages(at sourcePath: String, forLinux:Bool, inDockerImage imageName: String) throws -> ProcessResult
    @discardableResult func updatePackages(at sourcePath: String, forLinux: Bool, inDockerImage imageName: String) throws -> ProcessResult
    @discardableResult func build(source sourcePath: String, usingConfiguration configuration:BuildConfiguration, inDockerImage imageName: String, removeWhenDone: Bool) throws -> ProcessResult
    @discardableResult func clean(sourcePath: String) throws -> ProcessResult
    @discardableResult func symlinkDependencies(sourcePath: String) throws
    @discardableResult func createArchive(at archivePath: String, with filePaths: [String], flatList: Bool) throws -> ProcessResult
    @discardableResult func uploadArchive(at archivePath: String, to s3Bucket: String, in region: String, key: String, secret: String) throws
    @discardableResult func uploadArchive(at archivePath: String, to s3Bucket: String, in region: String, using credentialsPath: String) throws
    @discardableResult func incrementGitTag(components: [GitTagComponent], at sourcePath: String) throws -> String
    func gitTag(tag: String, at sourcePath: String) throws
    func pushGitTag(tag: String, at sourcePath: String) throws
    @discardableResult func createXcarchive(in dirPath: String, with binaryPath: String, from schemeName: String) throws -> String
}
