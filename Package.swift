import PackageDescription

/*
 Doesn't need to be built and tested in linux, it should only be ran from macOS
 */

let package = Package(
    name: "XcodeHelperKit",
    dependencies: [
        .Package(url: "https://github.com/saltzmanjoelh/ProcessRunner.git", versions: Version(0,0,0)..<Version(10,0,0)),
        .Package(url: "https://github.com/saltzmanjoelh/DockerProcess.git", versions: Version(0,0,0)..<Version(10,0,0)),
        .Package(url: "https://github.com/saltzmanjoelh/CliRunnable.git", versions: Version(0,0,0)..<Version(10,0,0)),
        .Package(url: "https://github.com/saltzmanjoelh/S3Kit.git", versions: Version(0,0,0)..<Version(10,0,0))
    ]
)
