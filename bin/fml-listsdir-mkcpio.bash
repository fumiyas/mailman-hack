#!/bin/bash
##
## FML 4: Archive FML lists directory into a cpio + gzip file for migration
## Copyright (c) 2022 SATOH Fumiyas @ OSSTech Corp., Japan
##
## License: GNU General Public License version 3
##

set -u
set -o pipefail || exit $?		## bash 3.0+

perr() {
  echo "$0: ERROR: $1" 1>&2
}

pdie() {
  perr "$1"
  exit "${2-1}"
}

## ======================================================================

getopts_want_arg()
{
  if [[ $# -lt 2 ]]; then
    pdie "Option requires an argument: $1"
  fi
  if [[ -n ${3:+set} ]]; then
    if [[ $2 =~ $3 ]]; then
      : OK
    else
      pdie "Invalid value for option: $1: $2"
    fi
  fi
  if [[ -n ${4:+set} ]]; then
    if [[ $2 =~ $4 ]]; then
      pdie "Invalid value for option: $1: $2"
    fi
  fi
}

## ----------------------------------------------------------------------

export without_htdocs_p="set"
export without_spool_p=""

while [[ $# -gt 0 ]]; do
  opt="$1"; shift

  if [[ -z "${opt##-[!-]?*}" ]]; then
    set -- "-${opt#??}" ${1+"$@"}
    opt="${opt%"${1#-}"}"
  fi
  if [[ -z "${opt##--*=*}" ]]; then
    set -- "${opt#--*=}" ${1+"$@"}
    opt="${opt%%=*}"
  fi

  case "$opt" in
  --with-htdocs)
    without_htdocs_p=""
    ;;
  -S|--without-spool)
    without_spool_p="set"
    ;;
  --)
    break
    ;;
  -*)
    pdie "Invalid option: $opt"
    ;;
  *)
    set -- "$opt" ${1+"$@"}
    break
    ;;
  esac
done

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

## ======================================================================

fml_lists_dir="$1"; shift
cpio_gz="$1"; shift

(
  cd "$(dirname "$fml_lists_dir")" || exit $?
  # shellcheck disable=SC2016 # Expressions don't expand in single quotes, use double quotes for that
  find "$(basename "$fml_lists_dir")/" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    ! -name '@*' \
    ! -name '-*' \
    -print0 \
  |xargs -0 sh -"${-//[!x]}c" '
    find \
      "$@" \
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
      ! -name ".crc" \
      ! -name log \
      ! -name summary \
      ! -name "actives.[0-9]" \
      ! -name "actives.[0-9][0-9]" \
      ! -name "members.[0-9]" \
      ! -name "members.[0-9][0-9]" \
      ! -name "fmlwrapper.[ch]" \
      ! -name "*.bak" \
      ! -name "*.db" \
      ! -name "*.dir" \
      ! -name "*.pag" \
      ! -name "*.old" \
      -type f \
      -print0 \
    ' sh \
  |cpio  \
    --quiet \
    --create \
    --null \
    --owner 0:0 \
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
