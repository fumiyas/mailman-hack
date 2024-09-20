#!/bin/sh
##
## Mailman 2.1: Disable command mail addresses in the aliases file
## Copyright (c) 2024 SATOH Fumiyas @ OSSTech Corp., Japan
##               <https://www.OSSTech.co.jp/>
##
## 1.  Install this script:
##
##     ```
##     # install -m 0755 mailman-postalias.sh /opt/site/sbin/mailman-postalias
##     ```
##
## 2.  Set POSTFIX_ALIAS_CMD and POSTFIX_MAP_CMD in mm_cfg.py:
##
##     ```
##     POSTFIX_ALIAS_CMD = '/opt/site/sbin/mailman-postalias'
##     POSTFIX_MAP_CMD = '/opt/site/sbin/mailman-postalias'
##     ```
##
## 3.  Re-generate the Mailman aliases files:
##
##     ```
##     # genaliases
##     ```

set -u
set -e

postalias='/usr/sbin/postalias'
postmap='/usr/sbin/postmap'

aliases="$1"; shift

case "${aliases##*/}" in
aliases)
  generator="$postalias"
  ;;
virtual-mailman)
  generator="$postmap"
  ;;
*)
  echo "$0: ERROR: Unknown alias filename: $aliases" 1>&2
  exit 1
  ;;
esac

## 1. On a stanza line, save a listname into hold space and start next
## 2. Append `\n<listname>` to pattern space
## 3. If a line is `<listname>-join...` or so on, delete a line and start next
## 4. Remove `\n<listname>` in pattern space
sed -E -i \
  -e '/^# STANZA START: / { p; s/.* //; h; d; }' \
  -e 'G' \
  -e '/^([^#:@]+)-(join|leave|request|subscribe|unsubscribe)[:@].+\n\1$/d' \
  -e 's/\n.*$//' \
  "$aliases" \
;

exec "$generator" "$aliases"
exit $?
