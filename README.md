XcodeHelperKit keeps you in Xcode and off the command line. You can:

* Build and run tests on Linux through Docker
* Fetch/Update Swift packages
* Keep your "Dependencies" group / Packages in Xcode referencing the correct paths
* Tar and upload you Linux binary to AWS S3 buckets

Combining all these features gives Xcode and Xcode Server the ability to handle the continuous integration and delivery for both macOS and Linux (via Docker) so that we don't have to use an intermediary build server like Jenkins.

This kit is what [XcodeHelper](https://github.com/saltzmanjoelh/XcodeHelper) and [XcodeHelperCli](https://github.com/saltzmanjoelh/XcodeHelperCli) are based off this framework.

There is an [example project](https://github.com/saltzmanjoelh/XcodeHelperExample) available to see the full configuration.

