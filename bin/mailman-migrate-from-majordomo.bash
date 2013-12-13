#!/bin/bash
##
## Mailman 2: Migrate from Majordomo
## Copyright (c) 2013 SATOH Fumiyas @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##

set -u

export PATH="/opt/osstech/sbin:/usr/sbin:$PATH"

function pinfo {
  echo "INFO: $1"
}

function perr {
  echo "$cmd_arg0: ERROR: $1" 1>&2
}

function pdie {
  perr "$1"
  exit ${2-1}
}

function run {
  pinfo "Run command: $*"
  "$@"
}

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 DOMAIN URLHOST ALIASES DIR"
  echo
  echo "DOMAIN	Mailing list domain"
  echo "URLHOST	Mailing list hostname for for Mailman Web UI"
  echo "ALIASES	Majordomo mail aliases file"
  echo "DIR	Majordomo directory"
  exit 1
fi

domain="$1"; shift
url_host="$1"; shift
md_alias_file="$1"; shift
md_dir="$1"; shift

${0%/*}/majordomo-dump-conf.pl "$domain" "$md_alias_file" "$md_dir" \
  |while IFS="	" read -r name domain owners owner_pass subject_prefix postid; do
    md_list="$md_dir/$name"
    if ! [ -f "$md_list" ]; then
      perr "No Majordomo list file: $name ($md_list)"
      continue
    fi

    owner="${owner%%,*}"
    subject_prefix="${subject_prefix//\$LIST/$name}"
    subject_prefix="${subject_prefix//\$SEQNUM/%d}"

    run newlist \
      --quiet \
      --emailhost="$domain" \
      --urlhost="$url_host" \
      "$name" \
      "$owner" \
      "$owner_pass" \
      || pdie "Mailman newslit failed: $?" \
    ;

    run add_members \
      --regular-members-file="$md_list" \
      --admin-notify=n \
      --welcome-msg=n \
      "$name" \
      || pdie "Mailman add_members failed: $?" \
    ;

    {
      echo "m.subject_prefix = '''$subject_prefix'''"
      if [[ -n $postid ]]; then
	echo "m.post_id = $postid"
      fi
      if [[ $owner != $owners ]]; then
	echo "m.owner += ["
	echo "'''${owners//,/''','''}'''"
	echo ']'
      fi
    } \
      |tee -a /dev/stderr \
      |run withlist --quiet --lock "$name" \
      || pdie "Mailman withlist failed: $?" \
    ;
  done \
;

