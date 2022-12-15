#!/bin/bash
##
## FML 4: Archive FML lists directory into a cpio + gzip file for migration
## Copyright (c) 2022 SATOH Fumiyas @ OSSTech Corp., Japan
##
## License: GNU General Public License version 3
##

set -u
set -o pipefail || exit $?		## bash 3.0+

without_htdocs_p="set"
if [[ ${1-} == @(--with-htdocs) ]]; then
  shift
  without_htdocs_p=""
fi
without_spool_p=""
if [[ ${1-} == @(-S|--without-spool) ]]; then
  shift
  without_spool_p="set"
fi

if [[ $# != 2 ]]; then
  prog_name="${0##*/}"
  cat <<-EOF
Usage: $prog_name [OPTIONS] FML_LISTS_DIR OUPUTO_CPIO_GZ

Options:
-S, --without-spool
    Exclude spool directory
--with-htdocs
    Include htdocs directory

Example: $prog_name /var/spool/ml fml-lists.cpio.gz
EOF
  exit 1
fi

fml_lists_dir="$1"; shift
cpio_gz="$1"; shift

(
  cd "$fml_lists_dir" || exit $?
  # shellcheck disable=SC2185 # finds don't have a default path. Specify '.' explicitly
  find . \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    ! -name '@*' \
    -print0 \
  |find \
    -files0-from - \
    -mindepth 1 \
    -maxdepth 3 \
    -type d \( \
      -name var -o \
      ${without_htdocs_p:+-name htdocs -o} \
      ${without_spool_p:+-name spool -o} \
      -false \
    \) \
    -prune \
    -o \
    ! -name '.crc' \
    ! -name log \
    ! -name summary \
    ! -name 'actives.[0-9]' \
    ! -name 'actives.[0-9][0-9]' \
    ! -name 'members.[0-9]' \
    ! -name 'members.[0-9][0-9]' \
    ! -name 'fmlwrapper.[ch]' \
    ! -name '*.bak' \
    ! -name '*.db' \
    ! -name '*.dir' \
    ! -name '*.pag' \
    ! -name '*.old' \
    -type f \
    -print0 \
  |cpio  \
    --quiet \
    -0 \
    -o \
  ;
) \
|gzip \
>"$cpio_gz" \
;

ret="$?"
if [[ $ret != 0 ]]; then
  rm -f "$cpio_gz"
  exit "$ret"
fi

exit 0
