#!/bin/bash
##
## Mailman 2: Compare lists configuration
## Copyright (c) 2013-2015 SATOH Fumiyas @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##

set -u

mm_dir="${MAILMAN_DIR-/opt/osstech/lib/mailman}"
mm_bin_dir="${MAILMAN_BIN_DIR-$mm_dir/bin/mailman}"
mm_var_dir="${MAILMAN_VAR_DIR-/opt/osstech/var/lib/mailman}"
mm_lists_dir="${MAILMAN_LISTS_DIR-$mm_var_dir/lists}"

a="$1"; shift
b="$1"; shift

dumpdb() {
  m="${1,,}"; shift

  ## Dump DB and normalaize values
  "$mm_bin_dir/dumpdb" "$mm_lists_dir/$m/config.pck" \
  |sed \
    -e 's/True,$/1,/' \
    -e 's/False,$/0,/' \
  ;
}

diff -uw \
  <(dumpdb "$a") \
  <(dumpdb "$b") \
|sed \
  -e "1s/.*/--- $a/" \
  -e "2s/.*/+++ $b/" \
;

