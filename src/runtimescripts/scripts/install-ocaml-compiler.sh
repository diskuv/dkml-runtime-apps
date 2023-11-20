#!/bin/sh
# ----------------------------
# install-ocaml.sh DKMLDIR GIT_TAG_OR_COMMIT DKMLHOSTABI INSTALLDIR CONFIGUREARGS

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

# Move binaries from bin/ to usr/bin/
move_bin() {
    mv -v "$INSTALLDIR/bin/$1" "$INSTALLDIR/usr/bin/$1"
}
move_bin_if_found() {
    if [ -e "$INSTALLDIR/bin/$1" ]; then
        move_bin "$1"
    fi
}

if is_unixy_windows_build_machine; then
    exe_ext=.exe
    move_bin_if_found flexdll_initer_msvc64.obj # windows_x86_64
    move_bin_if_found flexdll_initer_msvc.obj	# windows_x86
    move_bin_if_found flexdll_msvc64.obj    # windows_x86_64
    move_bin_if_found flexdll_msvc.obj      # windows_x86
    move_bin flexlink.exe
else
    exe_ext=
fi
move_bin ocaml$exe_ext
move_bin_if_found ocamlc.byte$exe_ext
move_bin ocamlc$exe_ext
move_bin_if_found ocamlc.opt$exe_ext
move_bin_if_found ocamlcmt$exe_ext
move_bin_if_found ocamlcp.byte$exe_ext
move_bin ocamlcp$exe_ext
move_bin_if_found ocamlcp.opt$exe_ext
move_bin_if_found ocamldebug$exe_ext
move_bin_if_found ocamldep.byte$exe_ext
move_bin ocamldep$exe_ext
move_bin_if_found ocamldep.opt$exe_ext
move_bin_if_found ocamldoc$exe_ext
move_bin_if_found ocamldoc.opt$exe_ext
move_bin_if_found ocamllex.byte$exe_ext
move_bin ocamllex$exe_ext
move_bin_if_found ocamllex.opt$exe_ext
move_bin_if_found ocamlmklib.byte$exe_ext
move_bin ocamlmklib$exe_ext
move_bin_if_found ocamlmklib.opt$exe_ext
move_bin_if_found ocamlmktop.byte$exe_ext
move_bin_if_found ocamlmktop$exe_ext
move_bin_if_found ocamlmktop.opt$exe_ext
move_bin_if_found ocamlobjinfo.byte$exe_ext
move_bin ocamlobjinfo$exe_ext
move_bin_if_found ocamlobjinfo.opt$exe_ext
move_bin_if_found ocamlopt.byte$exe_ext
move_bin_if_found ocamlopt$exe_ext
move_bin_if_found ocamlopt.opt$exe_ext
move_bin_if_found ocamloptp.byte$exe_ext
move_bin_if_found ocamloptp$exe_ext
move_bin_if_found ocamloptp.opt$exe_ext
move_bin_if_found ocamlprof.byte$exe_ext
move_bin_if_found ocamlprof$exe_ext
move_bin_if_found ocamlprof.opt$exe_ext
move_bin ocamlrun$exe_ext
move_bin_if_found ocamlrund$exe_ext
move_bin_if_found ocamlruni$exe_ext
move_bin ocamlyacc$exe_ext
move_bin_if_found ocamlnat$exe_ext
