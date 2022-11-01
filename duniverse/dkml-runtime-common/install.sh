#!/bin/sh

targetdir=$1
shift

echo -- ---------------------
echo Arguments:
echo "  Target directory = $targetdir"
echo -- ---------------------

install -d "$targetdir/unix" "$targetdir/all/emptytop"

install META "$targetdir/"
#       Since .template.dkmlroot goes into library, we drop the leading dot to avoid any future findlib problems
install .template.dkmlroot "$targetdir/template.dkmlroot"
install unix/_common_tool.sh unix/_within_dev.sh unix/crossplatform-functions.sh "$targetdir/unix/"
install all/emptytop/dune-project "$targetdir/all/emptytop/"
