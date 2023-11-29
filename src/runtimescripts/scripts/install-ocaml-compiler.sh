#!/bin/sh
# ----------------------------
# install-ocaml-compiler.sh DKMLDIR GIT_TAG_OR_COMMIT DKMLHOSTABI INSTALLDIR CONFIGUREARGS

set -euf

DKMLDIR=$1
shift
if [ ! -e "$DKMLDIR/.dkmlroot" ]; then echo "Expected a DKMLDIR at $DKMLDIR but no .dkmlroot found" >&2; fi

GIT_TAG_OR_COMMIT=$1
shift

DKMLHOSTABI=$1
shift

INSTALLDIR=$1
shift

if [ $# -ge 1 ]; then
    CONFIGUREARGS=$1
    shift
else
    CONFIGUREARGS=
fi

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/crossplatform-functions.sh

# Because Cygwin has a max 260 character limit of absolute file names, we place the working directories in /tmp. We do not need it
# relative to TOPDIR since we are not using sandboxes.
if [ -z "${DKML_TMP_PARENTDIR:-}" ]; then
    DKML_TMP_PARENTDIR=$(mktemp -d /tmp/dkmlp.XXXXX)

    # Change the EXIT trap to clean our shorter tmp dir
    trap 'rm -rf "$DKML_TMP_PARENTDIR"' EXIT
fi

# Keep the create_workdir() provided temporary directory, even when we switch
# into the reproducible directory so the reproducible directory does not leak
# anything
export DKML_TMP_PARENTDIR

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the DKMLDIR (just like the container
# sets the directory to be /work)
cd "$DKMLDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# Install the source code
log_trace "$DKMLDIR"/vendor/dkml-compiler/src/r-c-ocaml-1-setup.sh \
    -d "$DKMLDIR" \
    -t "$INSTALLDIR" \
    -v "$GIT_TAG_OR_COMMIT" \
    -e "$DKMLHOSTABI" \
    -k vendor/dkml-compiler/env/standard-compiler-env-to-ocaml-configure-env.sh \
    -m "$CONFIGUREARGS" \
    -z

# Use reproducible directory created by setup
cd "$INSTALLDIR"

# Build and install OCaml (but no cross-compilers)
log_trace "$SHARE_REPRODUCIBLE_BUILD_RELPATH"/100co/vendor/dkml-compiler/src/r-c-ocaml-2-build_host-noargs.sh

# Trim the installation
log_trace "$SHARE_REPRODUCIBLE_BUILD_RELPATH"/100co/vendor/dkml-compiler/src/r-c-ocaml-9-trim-noargs.sh
