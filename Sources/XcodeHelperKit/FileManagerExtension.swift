//
//  FileManagerExtension.swift
//  XcodeHelper
//
//  Created by Joel Saltzman on 2/28/17.
//  Copyright © 2017 Joel Saltzman. All rights reserved.
//

import Foundation

extension FileManager {
    
    public func modificationDateOfFile(path:String) -> NSDate? {
        guard let attributes = try? self.attributesOfItem(atPath: path) else { return nil }
        return attributes[FileAttributeKey.modificationDate] as? NSDate
    }
    
//    func creationDateForOfFile(path:String) -> NSDate? {
//        guard let attributes = try? self.attributesOfItem(atPath: path) else { return nil }
//        return attributes[FileAttributeKey.creationDate] as? NSDate
//    }
    
    public func recursiveContents(of directory: URL) -> [URL]? {
        guard let directoryContents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil , options: []) else { return nil }
        let subdirectoryContents = directoryContents.compactMap({ (url: URL) -> [URL]? in
            var URLs = [url]
            if url.hasDirectoryPath {
                if let subURLs = recursiveContents(of: url) {
                    URLs += subURLs
                }
            }
            return URLs
        })
        return subdirectoryContents.flatMap({ $0 })
    }
}
