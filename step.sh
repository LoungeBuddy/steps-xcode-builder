#!/bin/bash

echo "$ cd $CONCRETE_SOURCE_DIR"
cd $CONCRETE_SOURCE_DIR

if [[ $CONCRETE_PROJECT_PATH == *".xcodeproj" ]]; then
  export XCODE_PROJECT_ACTION="-project $CONCRETE_PROJECT_PATH"
elif [[ $CONCRETE_PROJECT_PATH == *".xcworkspace" ]]; then
  export XCODE_PROJECT_ACTION="-workspace $CONCRETE_PROJECT_PATH"
else
  echo "Failed to get valid project file: $CONCRETE_PROJECT_PATH"
  exit 1
fi

# Create directory structure
$CONCRETE_STEP_DIR/create_directory_structure.sh

if [ -n "$CONCRETE_ACTION_BUILD" ]; then
  export XCODEBUILD_ACTION="clean build"
fi

if [ -n "$CONCRETE_ACTION_ANALYZE" ]; then
  export XCODEBUILD_ACTION="analyze"
fi

# if [ -n "$CONCRETE_ACTION_TEST" ]; then
#   export XCODEBUILD_ACTION="clean test"
# fi

export ARCHIVE_PATH=$CONCRETE_DEPLOY_DIR/$CONCRETE_SCHEME.xcarchive
if [ -n "$CONCRETE_ACTION_ARCHIVE" ]; then
  export XCODEBUILD_ACTION="archive -archivePath \"$ARCHIVE_PATH\""
fi

if [ -n "$CONCRETE_ACTION_EXPORT_ARCHIVE" ]; then
  export EXPORT_PATH=$CONCRETE_DEPLOY_DIR/$CONCRETE_SCHEME.ipa
  export XCODEBUILD_ACTION="-exportArchive"
fi

# Get provisioning profile
export PROVISION_PATH=$CONCRETE_PROFILE_DIR/profile.mobileprovision
curl -so $PROVISION_PATH $CONCRETE_PROVISION_URL

# Get certificate
export CERTIFICATE_PATH=$CONCRETE_PROFILE_DIR/Certificate.p12
curl -so $CERTIFICATE_PATH $CONCRETE_CERTIFICATE_URL

$CONCRETE_STEP_DIR/keychain.sh add

# Get UUID & install provision profile
uuid_key=$(grep -aA1 UUID $PROVISION_PATH)
export PROFILE_UUID=$([[ $uuid_key =~ ([-A-Z0-9]{36}) ]] && echo ${BASH_REMATCH[1]})
cp $PROVISION_PATH "$CONCRETE_LIBRARY_DIR/$PROFILE_UUID.mobileprovision"

# Get identities
$CONCRETE_STEP_DIR/keychain.sh get-identity

# Start the build
if [ -n "$CONCRETE_ACTION_BUILD" ] || [ -n "$CONCRETE_ACTION_ANALYZE" ] || [ -n "$CONCRETE_ACTION_ARCHIVE" ]; then
  xcodebuild \
    $XCODE_PROJECT_ACTION \
    -scheme $CONCRETE_SCHEME \
    $XCODEBUILD_ACTION \
    OBJROOT=$CONCRETE_OBJ_ROOT \
    SYMROOT=$CONCRETE_SYM_ROOT \
    CODE_SIGN_IDENTITY="$CERTIFICATE_IDENTITY" \
    PROVISIONING_PROFILE="$PROFILE_UUID" \
    OTHER_CODE_SIGN_FLAGS="--keychain $CONCRETE_KEYCHAIN_PATH"
fi

if [ -n "$CONCRETE_ACTION_ARCHIVE" ]; then
  xcodebuild \
    $XCODEBUILD_ACTION \
    -exportFormat IPA \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportWithOriginalSigningIdentity
fi

if [ $? -eq 0 ]; then
  export XCODEBUILD_STATUS="succeeded"
else
  export XCODEBUILD_STATUS="failed"
fi

export CONCRETE_STATUS=$XCODEBUILD_STATUS

unset UUID
rm "$CONCRETE_LIBRARY_DIR/$PROFILE_UUID.mobileprovision"
$CONCRETE_STEP_DIR/keychain.sh remove

# Remove downloaded files
rm $PROVISION_PATH
rm $CERTIFICATE_PATH