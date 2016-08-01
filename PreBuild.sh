#First we run swift package fetch to get this LinuxRunners package
#Then we run sh Packages/LinuxRunners-1.0.0/PreBuild.sh to execute this script
#This scripts will run swift build on the LinuxRunners package. We only want to run it on the LinuxRunners package because the package that depends on it might have a Packages directory left over from a prior build that contains Linux specific dependencies in it that might cause build errors.
#Once the LinuxRunners package is built we can do things like:
#   check for prior linux build and clean (check .build/debug.yaml and .build/release.yaml for x86_64-apple, we may need to clean before building)
#   swift build on parent directory
#   update symlinks

#build the LinuxRunner

echo "fetching packages"
xcrun swift package fetch
HELPER_PATH=`dirname $0`
cd $HELPER_PATH
echo $(PWD)

echo "building"
xcrun swift build

