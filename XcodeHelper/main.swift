//xcode -> swift package fetch
//PreBuild -> Packages/XcodeHelpers*/ 

import XcodeHelperKit
import Foundation

let helper = XcodeHelper()
helper.run(arguments:ProcessInfo.processInfo.arguments, environment:ProcessInfo.processInfo.environment)
