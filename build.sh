# !/usr/bin/env bash
#
# Copyright (c) 2012, The Linux Foundation. All rights reserved.
# Copyright (C) 2023, StatiXOS
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit

usage() {
cat <<USAGE

Usage:
    bash $0 <TARGET_PRODUCT> [OPTIONS]

Description:
    Builds Android tree for given TARGET_PRODUCT

OPTIONS:
    -c, --clean_build
        Clean build - build from scratch by removing entire out dir

    -d, --debug
        Enable debugging - captures all commands while doing the build

    -h, --help
        Display this help message

    -i, --image
        Specify image to be build/re-build (bootimg/sysimg/usrimg)

    -j, --jobs
        Specifies the number of jobs to run simultaneously (Default: 8)

    -m, --module
        Module to be build

    -p, --package-type
        Specifies package type to build (Default: otapackage)

    -s, --sixtyfour-bits
        Builds a 64-bit only package if supported by the device tree

    -u, --udc
        Sets STATIX_BUILD_TYPE=UpsideDownCake

    -v, --build_variant
        Build variant (Default: userdebug)

USAGE
}

clean_build() {
    echo -e "\nINFO: Removing entire out dir. . .\n"
    m clobber
}

build_android() {
    echo -e "\nINFO: Build Android tree for $TARGET\n"
    m $@
}

build_bootimg() {
    echo -e "\nINFO: Build bootimage for $TARGET\n"
    m bootimage $@
}

build_sysimg() {
    echo -e "\nINFO: Build systemimage for $TARGET\n"
    m systemimage $@
}

build_usrimg() {
    echo -e "\nINFO: Build userdataimage for $TARGET\n"
    m userdataimage $@
}

build_module() {
    echo -e "\nINFO: Build $MODULE for $TARGET\n"
    m $MODULE $@
}

exit_on_error() {
    exit_code=$1
    last_command=${@:2}
    if [ $exit_code -ne 0 ]; then
        >&2 echo "\"${last_command}\" command failed with exit code ${exit_code}."
        exit $exit_code
    fi
}

# Device sync related
get_target_dirs() {
  local manifest_file="$1"
  target_dirs=$(grep -E 'path="[^"]+"' "$manifest_file" | awk -F'"' '{print $2}')
  echo "${target_dirs:-""}"  # Handle potential empty or missing value
}

# Set defaults
VARIANT="userdebug"
JOBS=$(nproc --all)

# Setup getopt.
long_opts="clean_build,debug,help,image:,jobs:,module:,"
long_opts+="sixtyfour-bits,package-type:,udc,build_variant:"
getopt_cmd=$(getopt -o cdhi:j:k:m:p:suv: --long "$long_opts" \
            -n $(basename $0) -- "$@") || \
            { echo -e "\nERROR: Getopt failed. Extra args\n"; usage; exit 1;}

eval set -- "$getopt_cmd"

while true; do
    case "$1" in
        -c|--clean_build) CLEAN_BUILD="true";;
        -d|--debug) DEBUG="true";;
        -h|--help) usage; exit 0;;
        -i|--image) IMAGE="$2"; shift;;
        -j|--jobs) JOBS="$2"; shift;;
        -m|--module) MODULE="$2"; shift;;
        -p|--package-type) PKG="$2"; shift;;
        -s|--sixtyfour-bits) SIXTYFOUR_BITS="true";;
        -u|--udc) UDC="true";;
        -v|--build_variant) VARIANT="$2"; shift;;
        --) shift; break;;
    esac
    shift
done

# Mandatory argument
if [ $# -eq 0 ]; then
    echo -e "\nERROR: Missing mandatory argument: TARGET_PRODUCT\n"
    usage
    exit 1
fi
if [ $# -gt 1 ]; then
    echo -e "\nERROR: Extra inputs. Need TARGET_PRODUCT only\n"
    usage
    exit 1
fi

case "$PKG" in
    "")
        PKG="bacon" ;;
    "otapackage")
        PKG="bacon" ;;
    "updatepackage")
        PKG="updatepackage" ;;
    "targetfiles")
        PKG="target-files-package otatools" ;;
    *)
        echo "Unknown package type! Bailing out!" && exit 1 ;;
esac

TARGET="$1"; shift

CMD="-j $JOBS"
if [ "$DEBUG" = "true" ]; then
    CMD+=" showcommands"
fi

source build/envsetup.sh

if [ -d "device/*/$TARGET" ]; then
    echo "Device tree found"
else
    echo "Checking if tree exists in manifests"
    if test -f "device/manifests/$TARGET.xml"; then
        echo "Syncing $TARGET trees"
        target_dirs=$(get_target_dirs "device/manifests/$TARGET.xml")
        # Clear older manifests
        if ! [ -d .repo/local_manifests ]; then
            mkdir -p .repo/local_manifests/
        else
            rm -rf .repo/local_manifests/*.xml
        fi
        cp device/manifests/$TARGET.xml .repo/local_manifests/$TARGET.xml

        # Loop through each extracted target directory and sync
        if [[ ! -z "$target_dirs" ]]; then
            IFS=$'\n' read -r -a target_dir_array <<< "$target_dirs"
            for dir in "${target_dir_array[@]}"; do
                repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags "$dir"
            done
        else
            echo "Error: Target directories not found in $manifest_file"
            exit_on_error
        fi
    fi
fi

if [ "$UDC" = "true" ]; then
    export STATIX_BUILD_TYPE=UpsideDownCake
fi

if [ "$SIXTYFOUR_BITS" = "true" ]; then
    lunch statix_${TARGET}_64-ap2a-$VARIANT || exit_on_error
else
    lunch statix_$TARGET-ap2a-$VARIANT || exit_on_error
fi
m installclean

if [ "$CLEAN_BUILD" = "true" ]; then
    clean_build
fi

if [ -n "$MODULE" ]; then
    build_module "$CMD"
fi

if [ -n "$IMAGE" ]; then
    build_$IMAGE "$CMD"
fi

build_android "$PKG" "$CMD"
