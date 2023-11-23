#!/bin/sh
##########################################################################
# File: dktool/cmake/scripts/dkml/workflow/compilers-build-test.in.sh    #
#                                                                        #
# Copyright 2022 Diskuv, Inc.                                            #
#                                                                        #
# Licensed under the Apache License, Version 2.0 (the "License");        #
# you may not use this file except in compliance with the License.       #
# You may obtain a copy of the License at                                #
#                                                                        #
#     http://www.apache.org/licenses/LICENSE-2.0                         #
#                                                                        #
# Unless required by applicable law or agreed to in writing, software    #
# distributed under the License is distributed on an "AS IS" BASIS,      #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or        #
# implied. See the License for the specific language governing           #
# permissions and limitations under the License.                         #
#                                                                        #
##########################################################################

# Updating
# --------
#
# 1. Delete this file.
# 2. Run dk with your original arguments:
#        ./dk dkml.workflow.compilers CI GitHub
#    or get help to come up with new arguments:
#        ./dk dkml.workflow.compilers HELP

set -euf

# Set project directory
if [ -n "${CI_PROJECT_DIR:-}" ]; then
    PROJECT_DIR="$CI_PROJECT_DIR"
elif [ -n "${PC_PROJECT_DIR:-}" ]; then
    PROJECT_DIR="$PC_PROJECT_DIR"
elif [ -n "${GITHUB_WORKSPACE:-}" ]; then
    PROJECT_DIR="$GITHUB_WORKSPACE"
else
    PROJECT_DIR="$PWD"
fi
if [ -x /usr/bin/cygpath ]; then
    PROJECT_DIR=$(/usr/bin/cygpath -au "$PROJECT_DIR")
fi

dkml_version=$(cat "$PROJECT_DIR/src/runtimelib/version.txt")

# shellcheck disable=SC2154
echo "
=============
build-test.sh
=============
.
----
DkML
----
dkml_version=$dkml_version
DISKUV_OPAM_REPOSITORY=${DISKUV_OPAM_REPOSITORY:-}
.
---------
Arguments
---------
$*
.
------
Matrix
------
dkml_host_abi=$dkml_host_abi
abi_pattern=$abi_pattern
opam_root=$opam_root
exe_ext=${exe_ext:-}
.
"

# PATH. Add opamrun
export PATH="$PROJECT_DIR/.ci/sd4/opamrun:$PATH"

# Initial Diagnostics (optional but useful)
opamrun switch
opamrun list
opamrun var
opamrun config report
opamrun option
opamrun exec -- ocamlc -config

# Update
opamrun update

# Let dkml-* packages use their own versions (the DkML version), not the pins from [dkml-workflows]
opamrun pin remove dkml-compiler-env --yes --no-action || true # dkml-compiler-env will disappear
opamrun pin dkml-compiler-src -k version "$dkml_version" --yes --no-action
opamrun pin dkml-runtime-common -k version "$dkml_version" --yes --no-action
opamrun pin dkml-runtime-distribution -k version "$dkml_version" --yes --no-action
opamrun upgrade dkml-compiler-src dkml-runtime-common dkml-runtime-distribution --yes

# Make your own build logic! It may look like ...
opamrun install . --deps-only --with-test --yes
case "$dkml_host_abi" in
darwin_x86_64)
    toolchain=darwin_arm64;;
*)
    toolchain=''
esac
if [ -n "$toolchain" ]; then
    opamrun exec -- dune build -x "$toolchain"
else
    opamrun exec -- dune build
fi

# ------------ Verbatim from diskuvbox (plus for OPAM_PKGNAME loop) --------------

# Prereq: Diagnostics
case "${dkml_host_abi}" in
linux_*)
    if command -v apk; then
        apk add file
    fi ;;
esac

# Copy the installed binaries (including cross-compiled ones) from Opam into dist/ folder.
# Name the binaries with the target ABI since GitHub Releases are flat namespaces.
install -d dist/
mv _build/install/default "_build/install/default.${dkml_host_abi}"
set +f
for OPAM_PKGNAME in dkml with-dkml; do
for i in _build/install/default.*; do
  target_abi=$(basename "$i" | sed s/default.//)
  if [ -e "_build/install/default.${target_abi}/bin/${OPAM_PKGNAME}.exe" ]; then
    install -v "_build/install/default.${target_abi}/bin/${OPAM_PKGNAME}.exe" "dist/${target_abi}-${OPAM_PKGNAME}.exe"
    file "dist/${target_abi}-${OPAM_PKGNAME}.exe"
  else
    install -v "_build/install/default.${target_abi}/bin/${OPAM_PKGNAME}" "dist/${target_abi}-${OPAM_PKGNAME}"
    file "dist/${target_abi}-${OPAM_PKGNAME}"
  fi
done
done

# For Windows you must ask your users to first install the vc_redist executable.
# Confer: https://github.com/diskuv/dkml-workflows#distributing-your-windows-executables
case "${dkml_host_abi}" in
windows_x86_64) wget -O dist/vc_redist.x64.exe https://aka.ms/vs/17/release/vc_redist.x64.exe ;;
windows_x86) wget -O dist/vc_redist.x86.exe https://aka.ms/vs/17/release/vc_redist.x86.exe ;;
windows_arm64) wget -O dist/vc_redist.arm64.exe https://aka.ms/vs/17/release/vc_redist.arm64.exe ;;
esac
