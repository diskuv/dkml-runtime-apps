#!/bin/sh
# ----------------------------
# restore-ocaml-shims.sh INSTALLDIR

set -euf

INSTALLDIR=$1
shift

# ----------------------------------------------
# We replace any with-dkml shims that were installed.
# That is:
#       ocaml       <newly installed by install-ocaml-compiler.sh>
#       ocaml-real  <originally installed>
#       with-dkml   <originally installed>
# becomes:
#       ocaml       <replaced with the contents of with-dkml>
#       ocaml-real  <untouched>
#       with-dkml   <untouched>

shimize=0
if [ -x "$INSTALLDIR/bin/with-dkml.exe" ]; then
    shimize=1
    exe_ext=.exe
elif [ -x "$INSTALLDIR/bin/with-dkml" ]; then
    shimize=1
    exe_ext=
fi
if [ "$shimize" = 1 ]; then
    for shim in ocamlc ocamlcp ocaml; do
        if [ -x "$INSTALLDIR/bin/$shim-real$exe_ext" ]; then
            install -v "$INSTALLDIR/bin/with-dkml$exe_ext" "$INSTALLDIR/bin/$shim$exe_ext"
        fi
    done
fi
