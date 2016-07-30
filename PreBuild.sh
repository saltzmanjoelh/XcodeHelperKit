#First we run swift package fetch to get this XcodeHelpers package
#Then we run sh Packages/XcodeHelpers-1.0.0/PreBuild.sh to execute this script
#This scripts will run swift build on the XcodeHelpers package. We only want to run it on the XcodeHelpers package because the package that depends on it might have a Packages directory that has Linux specific packages in it that might cause build errors.
#Once the XcodeHelpers package is built we can do things like:
#   check for prior linux build and clean (check .build/debug.yaml and .build/release.yaml for x86_64-apple, we may need to clean before building)
#   swift build on parent directory
#   update symlinks
echo "RUNNING PREBUILD!!!"
