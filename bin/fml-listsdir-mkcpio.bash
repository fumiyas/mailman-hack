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

## ----------------------------------------------------------------------

_cmds_at_exit=()

# shellcheck disable=SC2317
cmds_at_exit() {
  local cmd

  for cmd in "${_cmds_at_exit[@]}"; do
    "$cmd"
  done
}

trap 'cmds_at_exit' EXIT
for signal in HUP INT TERM; do
  trap 'cmds_at_exit; trap - EXIT '$signal'; kill -'$signal' -$$' $signal
done

## ----------------------------------------------------------------------

_temp_files=()
_cmds_at_exit+=(clean_tempfiles)

create_tempfile() {
  local vname="$1"; shift
  local fname

  if [[ $vname == *[!_0-9A-Za-z]* ]]; then
    perr "${FUNCNAME[0]}: Invalid variable name: $vname"
    return 1
  fi

  fname=$(mktemp "$@" "${TMPDIR:-/tmp}/${0##*/}.XXXXXXXX") || return $?
  _temp_files+=("$fname")
  eval "$vname=\"\$fname\""
}

# shellcheck disable=SC2317
clean_tempfiles() {
  [[ -n "${_temp_files[0]+set}" ]] && rm -rf "${_temp_files[@]}"
}

## ======================================================================

# shellcheck disable=SC2317
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

if [[ $# != 3 ]]; then
  prog_name="${0##*/}"
  cat <<-EOF
Usage: $prog_name [OPTIONS] FML_DIR FML_LISTS_DIR OUTPUT_CPIO_GZ

Options:
-S, --without-spool
    Exclude spool directory
--with-htdocs
    Include htdocs directory

Example: $prog_name /usr/local/fml /var/spool/ml fml-lists.cpio.gz
EOF
  exit 1
fi

fml_dir="$1"; shift
fml_lists_dir="$1"; shift
cpio_gz="$1"; shift

## ======================================================================

if [[ $fml_dir != /* ]]; then
  fml_dir="$PWD/$fml_dir"
fi
if [[ $fml_lists_dir != /* ]]; then
  fml_lists_dir="$PWD/$fml_lists_dir"
fi

create_tempfile tmp_dir -d || exit $?

# shellcheck disable=SC2154 # tmp_dir is referenced but not assigned
ln -s "$fml_dir" "$tmp_dir/" || exit $?
ln -s "$fml_lists_dir" "$tmp_dir/" || exit $?

(
  cd "$tmp_dir" || exit $?
  (
    find "$(basename "$fml_dir")/" \
      -type d \
      -name '[-.@]*' \
      -prune \
      -o \
      -type f \
      -name htpasswd \
       -print0 \
    ;
    # shellcheck disable=SC2016 # Expressions don't expand in single quotes
    find "$(basename "$fml_lists_dir")/" \
      -mindepth 1 \
      -maxdepth 1 \
      -type d \
      ! -name '[-.@]*' \
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
    ;
  ) \
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
