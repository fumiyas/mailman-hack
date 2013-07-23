#!/bin/ksh
##
## WARNING:
##	Cannot migrate $START_HOOK in fml cf
##

set -u
umask 0027

cmd_arg0="$0"

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

tmp_dir=$(mktemp -d /tmp/${0##*/}.XXXXXXXX) \
  || pdie "Cannot create temporary directory"
trap 'rm -rf "$tmp_dir"; trap - EXIT; exit 1' HUP INT
trap 'rm -rf "$tmp_dir"' EXIT

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

## ======================================================================

pinfo "Reading fml cf file"

typeset -A fml_cf
typeset -u cf_name

sed \
  -e 's/^ *&*DEFINE_FIELD_FORCED(.\(.*\)., *["'"'"']\?\(.*\)["'"'"']\?);/\1 \2/p' \
  cf \
|sed -n '/^[A-Za-z][A-Za-z_\-]*[ 	][ 	]*/p' \
|while read -r cf_name cf_value; do
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
  mm_subject_post_id_fmt='%d'
  if [[ -n ${fml_cf[SUBJECT_FORM_LONG_ID]-} ]]; then
    mm_subject_post_id_fmt="%0${fml_cf[SUBJECT_FORM_LONG_ID]}d"
  fi
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
  --urlhost="$mm_url_host" \
  "$ml_name" \
  "$mm_admin" \
  "$mm_admin_pass" \
  || exit 1

echo "$mm_admin_pass" >"$mm_ml_dir/adminpass" \
  || exit 1

## ======================================================================

pinfo "Migrating list configuration to Mailman"

{
  echo "m.real_name = '$ml_name'"
  echo "m.reject_these_nonmembers = ['^(${fml_cf[REJECT_ADDR]})@']"
  echo "m.subject_prefix = '$mm_subject_prefix'"
  echo "m.subscribe_policy = $mm_subscribe_policy"
  echo "m.generic_nonmember_action = $mm_generic_nonmember_action"
  echo "m.reply_goes_to_list = $mm_reply_goes_to_list"
  echo "m.archive_volume_frequency = $mm_archive_volume_frequency"

  if [[ -f members-admin ]]; then
    echo "m.owner += ["
    sed -n 's/\([^#].*\)/"\1",/p' members-admin
    echo ']'
  fi
  if [[ -f moderators ]]; then
    echo "m.moderator += ["
    sed -n 's/\([^#].*\)/"\1",/p' moderators
    echo ']'
  fi

  if [[ -n $mm_postid ]]; then
    echo "m.post_id = $mm_postid"
  fi

  echo "m.accept_these_nonmembers += ["
  diff \
    <(sed -n 's/^\([^# 	]*\).*$/\1/p;' members) \
    <(sed -n 's/^\([^# 	]*\).*$/\1/p;' actives) \
  |sed -n 's/^< \(.*\)$/"\1",/p' \
  ;
  echo ']'

  echo 'm.Save()'
} \
|tee /dev/stderr \
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

pinfo "Migrating list archive to Mailman"

from_dummy="From dummy  $(LC_ALL=C TZ= date +'%a %b %e %H:%M:%S %Y')"

ls spool 2>/dev/null \
|grep '^[1-9][0-9]*$' \
|sort -n \
|while read n; do \
  echo "$from_dummy"
  sed 's/^>*From />&/' "spool/$n"
  echo
done \
>"$mm_mbox.fml" \
;

if [[ ${fml_cf[AUTO_HTML_GEN]} -eq 1 && -s $mm_mbox.fml ]]; then
  run arch \
    --quiet \
    --wipe \
    "$ml_name" \
    "$mm_mbox.fml" \
    || exit 1
fi

## ======================================================================

exit 0

