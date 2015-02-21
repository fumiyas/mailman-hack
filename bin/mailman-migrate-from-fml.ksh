#!/bin/ksh
##
## Mailman 2: Migrate from fml 4.0
## Copyright (c) 2013-2015 SATOH Fumiyas @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##
## WARNING:
##	Cannot migrate $START_HOOK and so on in fml config.ph
##

set -u
umask 0027

cmd_arg0="$0"

function pinfo {
  echo "INFO: $1" 1>&2
}

function perr {
  echo "$cmd_arg0: ERROR: $1" 1>&2
}

function pdie {
  perr "$1"
  exit ${2-1}
}

function run {
  pinfo "Run command: $*" 1>&2
  if [[ -n ${NO_RUN+set} ]]; then
    [[ -t 0 ]] || cat >/dev/null
  else
    "$@"
  fi
}

tmp_dir=$(mktemp -d /tmp/${0##*/}.XXXXXXXX) \
  || pdie "Cannot create temporary directory"
trap 'rm -rf "$tmp_dir"; trap - EXIT; exit 1' HUP INT
trap 'rm -rf "$tmp_dir"' EXIT

mm_user="${MM_USER-mailman}"
mm_sbin_dir="${MM_SBIN_DIR-/opt/osstech/sbin}"
mm_lists_dir="${MM_LISTS_DIR-/opt/osstech/var/lib/mailman/lists}"
mm_archive_dir="${MM_ARCHIVE_DIR-/opt/osstech/var/lib/mailman/archives}"

export PATH="$mm_sbin_dir:$(cd "${0%/*}" && pwd):$PATH" || exit 1
unset PYTHONPATH

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 FML_LIST_DIR [URL_HOST]"
  exit 1
fi

fml_list_dir="$1"; shift
mm_url_host="${1-}"; ${1+shift}

typeset -l ml_name_lower
ml_name="${fml_list_dir##*/}"
ml_name_lower="$ml_name"
mm_ml_dir="$mm_lists_dir/$ml_name_lower"
if [[ -d $mm_ml_dir ]]; then
  pdie "Mailman list $ml_name already exists"
fi

cd "$fml_list_dir" || exit 1
if [[ ! -f config.ph ]]; then
  pdie "fml config.ph file not found"
fi

## ======================================================================

pinfo "Reading fml config.ph file"

typeset -A fml_cf
typeset -u cf_name

sed \
  -n \
  -e 's/^\$\([A-Za-z][A-Za-z_]*\)[ 	]*=[ 	]*\(.*\);$/\1 \2/p' \
  -e 's/^[ 	]*&*DEFINE_FIELD_FORCED(.\([^"'"'"']*\).[ 	]*,[ 	]*\([^)]*\).*$/\1 \2/p' \
  config.ph \
|while read -r cf_name cf_value; do
  cf_value="${cf_value#[\"\']}"
  cf_value="${cf_value%[\"\']}"
  cf_value="${cf_value//\\@/@}"
  fml_cf[$cf_name]="${cf_value/\$DOMAINNAME/${fml_cf[DOMAINNAME]-}}"
  #echo "fml_cf[$cf_name]='${fml_cf[$cf_name]}'"
done

## ======================================================================

pinfo "Constructing Mailman list configuration"

mm_admin="fml@${fml_cf[DOMAINNAME]}"
mm_postid=$(cat seq 2>/dev/null) && let mm_postid++
mm_mbox="$mm_archive_dir/private/$ml_name_lower.mbox/$ml_name_lower.mbox"
mm_admin_pass=$(printf '%04x%04x%04x%04x' $RANDOM $RANDOM $RANDOM $RANDOM)
mm_reply_goes_to_list=1 ## "Reply-To: This list" by default

if [[ ${fml_cf[AUTO_REGISTRATION_TYPE]} != 'confirmation' ]]; then
  pdie "$ml_name: AUTO_REGISTRATION_TYPE='${fml_cf[AUTO_REGISTRATION_TYPE]}' not supported"
fi

case "${fml_cf[PERMIT_POST_FROM]}" in
anyone)
  mm_generic_nonmember_action=0
  ;;
members_only)
  case "${fml_cf[REJECT_POST_HANDLER]}" in
  reject)
    mm_generic_nonmember_action=2
    ;;
  ignore)
    mm_generic_nonmember_action=3
    ;;
  *)
    perr "$ml_name: REJECT_POST_HANDLER='${fml_cf[REJECT_POST_HANDLER]}' not supported"
    ;;
  esac
  ;;
#moderator)
# FIXME
#  ;;
*)
  perr "$ml_name: PERMIT_POST_FROM='${fml_cf[PERMIT_POST_FROM]}' not supported"
  ;;
esac

#mm_subscribe_policy=2 ## Require approval
mm_subscribe_policy=3 ## Confirm and approve
if [[ ${fml_cf[PERMIT_COMMAND_FROM]} = 'anyone' ||
      ${fml_cf[REJECT_COMMAND_HANDLER]} = @(auto_subscribe|auto_regist) ]]; then
  mm_subscribe_policy=1 ## Confirm
fi

mm_subject_prefix=''
if [[ -n ${fml_cf[SUBJECT_TAG_TYPE]} ]]; then
  mm_subject_post_id_fmt="%0${fml_cf[SUBJECT_FORM_LONG_ID]-5}d"
  case "${fml_cf[SUBJECT_TAG_TYPE]}" in
  '( )'|'[ ]')
    mm_subject_prefix="${fml_cf[SUBJECT_TAG_TYPE]/ /${fml_cf[BRACKET]} $mm_subject_post_id_fmt}"
    ;;
  '(:)'|'[:]')
    mm_subject_prefix="${fml_cf[SUBJECT_TAG_TYPE]/:/${fml_cf[BRACKET]}:$mm_subject_post_id_fmt}"
    ;;
  '(,)'|'[,]')
    mm_subject_prefix="${fml_cf[SUBJECT_TAG_TYPE]/,/${fml_cf[BRACKET]},$mm_subject_post_id_fmt}"
    ;;
  '(ID)'|'[ID]')
    mm_subject_prefix="${fml_cf[SUBJECT_TAG_TYPE]/ID/$mm_subject_post_id_fmt}"
    ;;
  '()')
    mm_subject_prefix="(${fml_cf[SUBJECT_TAG_TYPE]})"
    ;;
  '[]')
    mm_subject_prefix="[${fml_cf[SUBJECT_TAG_TYPE]}]"
    ;;
  *)
    perr "$ml_name: SUBJECT_TAG_TYPE='${fml_cf[PERMIT_POST_FROM]}' invalid"
    ;;
  esac
  mm_subject_prefix="$mm_subject_prefix "
fi

mm_archive='True'
if [[ ${fml_cf[NOT_USE_SPOOL]-0} = 1 && ${fml_cf[AUTO_HTML_GEN]-0} != 1 ]]; then
  mm_archive='False'
fi

case "${fml_cf[HTML_INDEX_UNIT]-}" in
infinite)
  ## Yearly
  mm_archive_volume_frequency=0
  ;;
month)
  mm_archive_volume_frequency=1
  ;;
week)
  mm_archive_volume_frequency=3
  ;;
''|0|day)
  mm_archive_volume_frequency=4
  ;;
*)
  ## Monthly
  mm_archive_volume_frequency=1
  ;;
esac

## ======================================================================

pinfo "Creating Mailman list"

run newlist \
  --quiet \
  --emailhost="${fml_cf[DOMAINNAME]}" \
  ${mm_url_host+--urlhost="$mm_url_host"} \
  "$ml_name" \
  "$mm_admin" \
  "$mm_admin_pass" \
  || exit 1

echo "$mm_admin_pass" |run tee "$mm_ml_dir/adminpass" >/dev/null \
  || exit 1

## ======================================================================

pinfo "Migrating list configuration to Mailman"

{
  echo "m.real_name = '''$ml_name'''"
  echo "m.reject_these_nonmembers = ['''^(${fml_cf[REJECT_ADDR]})@''']"
  echo "m.subject_prefix = '''$mm_subject_prefix'''"
  echo "m.subscribe_policy = $mm_subscribe_policy"
  echo "m.generic_nonmember_action = $mm_generic_nonmember_action"
  echo "m.reply_goes_to_list = $mm_reply_goes_to_list"
  echo "m.archive = $mm_archive"
  echo "m.archive_volume_frequency = $mm_archive_volume_frequency"

  if [[ -f members-admin || -f include-admin ]]; then
    echo "m.owner += ["
    cat members-admin include-admin 2>/dev/null \
    |sed -n 's/\([^#].*\)/"""\1""",/p' \
    |sort -uf \
    ;
    echo ']'
  fi
  if [[ -f moderators ]]; then
    echo "m.moderator += ["
    sed -n 's/\([^#].*\)/"""\1""",/p' moderators
    echo ']'
  fi

  if [[ -n $mm_postid ]]; then
    echo "m.post_id = $mm_postid"
  fi

  ## FIXME: Add to members and call mlist.setDeliveryStatus(addr, MemberAdaptor.BYADMIN)
  echo "m.accept_these_nonmembers += ["
  diff -i \
    <(sed -n 's/^\([^# 	]*\).*$/\1/p;' members |sort -uf) \
    <(sed -n 's/^\([^# 	]*\).*$/\1/p;' actives |sort -uf) \
  |sed -n 's/^< \(.*\)$/"\1",/p' \
  ;
  echo ']'

  echo 'm.Save()'
} \
|tee >(sed 's/^/INFO: Mailman withlist: /' 1>&2) \
|run withlist --quiet --lock "$ml_name_lower" \
  || exit 1

echo

## ======================================================================

## FIXME: Migrate header filter

#header_filter=$(
#  sed -n 's/^ *&*DEFINE_FIELD_PAT_TO_REJECT(.\(.*\)., *.\(.*\).);/\1:.*\2/p' \
#    "$fml_cf_file" \
#    ;
#)

## ======================================================================

pinfo "Migrating list members to Mailman"

touch "$tmp_dir/$ml_name.regular-members" "$tmp_dir/$ml_name.digest-members"
sed -n '/^[^#]/p' actives \
|while read -r address options; do
  skip=
  digest=
  for option in $options; do
    case "$option" in
    s=skip|s=1)
      skip=set
      ;;
    m=[1-9]*)
      digest=set
      ;;
    esac
  done
  if [[ -n $skip ]]; then
    continue
  fi
  if [[ -n $digest ]]; then
    echo "$address" >>"$tmp_dir/$ml_name.digest-members"
  else
    echo "$address" >>"$tmp_dir/$ml_name.regular-members"
  fi
done \

run add_members \
  --regular-members-file="$tmp_dir/$ml_name.regular-members" \
  --digest-members-file="$tmp_dir/$ml_name.digest-members" \
  --welcome-msg=n \
  --admin-notify=n \
  "$ml_name" \
  || exit 1

## ======================================================================

if [[ -d spool ]] && ls -fF spool |grep '^[1-9][0-9]*$' >/dev/null; then
  pinfo "Migrating list archive to Mailman"

  from_dummy="From dummy  $(LC_ALL=C TZ= date +'%a %b %e %H:%M:%S %Y')"

  ls -fF spool \
  |grep '^[1-9][0-9]*$' \
  |sort -n \
  |while read n; do \
    echo "$from_dummy"
    sed 's/^>*From />&/' "spool/$n"
    echo
  done \
  >"$mm_mbox.fml" \
  ;

  run chown "$mm_user:" "$mm_mbox.fml"

  if [[ -s $mm_mbox.fml ]]; then
    run arch \
      --quiet \
      --wipe \
      "$ml_name" \
      "$mm_mbox.fml" \
      || exit 1
  fi
fi

## ======================================================================

exit 0

