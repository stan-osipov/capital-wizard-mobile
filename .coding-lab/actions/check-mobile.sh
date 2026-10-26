#!/bin/sh
# action: Check mobile apps
# description: Build both iOS products and build, unit-test and lint both Android flavors.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo"
mkdir -p .build
for scheme in capital-wizard-ios coding-lab-ios; do
    xcodebuild -project iOS/capital-wizard-ios.xcodeproj -scheme "$scheme" \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$repo/.build/ios" -clonedSourcePackagesDirPath "$repo/.build/packages" \
        CODE_SIGNING_ALLOWED=NO build
done
if [ -z "${JAVA_HOME:-}" ]; then
    for jdk in "$repo"/.build/tools/jdk-*/Contents/Home; do
        if [ -x "$jdk/bin/java" ]; then JAVA_HOME=$jdk; export JAVA_HOME; break; fi
    done
fi
ANDROID_HOME=${ANDROID_HOME:-"$repo/.build/android-sdk"}
GRADLE_USER_HOME="$repo/.build/gradle"
export ANDROID_HOME GRADLE_USER_HOME
cd Android
./gradlew --no-daemon --max-workers=2 assembleCapitalWizardDebug assembleCodingLabDebug \
    testCapitalWizardDebugUnitTest testCodingLabDebugUnitTest lintCapitalWizardDebug lintCodingLabDebug
