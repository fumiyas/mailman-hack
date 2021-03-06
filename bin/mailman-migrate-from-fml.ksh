#!/bin/ksh
##
## Mailman 2: Migrate from fml 4.0
## Copyright (c) 2013-2015 SATOH Fumiyas @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##
## WARNING:
##	Cannot migrate the following configuration in a fml config.ph:
##	  * $START_HOOK
##	  * &ADD_CONTENT_HANDLER() (FIXME)
##	  * and more...
##
## FIXME:
##	* Set m.default_member_moderation=True and m.member_moderation_action=1
##	  if members_only and actives!=members
##

set -u
umask 0027

export LC_ALL=C
unset PYTHONPATH

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

function fml_true_p {
  [[ ${1-} = @(|0) ]] && return 1
  return 0
}

tmp_dir=$(mktemp -d /tmp/${0##*/}.XXXXXXXX) \
  || pdie "Cannot create temporary directory"
trap 'rm -rf "$tmp_dir"; trap - EXIT; exit 1' HUP INT
trap 'rm -rf "$tmp_dir"' EXIT

#log="$tmp_dir/${0##*/}.$(date '+%Y%m%d.%H%M%S').log"
#exec 2> >(tee "$log" 1>&2)

mm_user="${MAILMAN_USER-mailman}"
mm_site_email="${MAILMAN_SITE_EMAIL-fml}"
mm_dir="${MAILMAN_DIR-/opt/osstech/lib/mailman}"
mm_var_dir="${MAILMAN_VAR_DIR-/opt/osstech/var/lib/mailman}"
mm_lists_dir="${MAILMAN_LISTS_DIR-$mm_var_dir/lists}"
mm_archives_dir="${MAILMAN_ARCHIVES_DIR-$mm_var_dir/archives}"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 FML_LIST_DIR FML_ALIASES [URL_HOST]"
  exit 1
fi

fml_list_dir="$1"; shift
fml_aliases="$1"; shift
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
  -e 's/^\$\([A-Za-z][A-Za-z_]*\)[ 	]*=[ 	]*\(.*\);[ 	]*$/\1 \2/p' \
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
mm_mbox="$mm_archives_dir/private/$ml_name_lower.mbox/$ml_name_lower.mbox"
mm_admin_pass=$(printf '%04x%04x%04x%04x' $RANDOM $RANDOM $RANDOM $RANDOM)
mm_max_message_size=$((${fml_cf[INCOMING_MAIL_SIZE_LIMIT]:-0} / 1000))
mm_max_days_to_hold="${fml_cf[MODELATOR_EXPIRE_LIMIT]:-14}"
## &DEFINE_FIELD_FORCED('reply-to',$MAIL_LIST);
## &DEFINE_FIELD_FORCED('Reply-To' , $From_address);
mm_reply_goes_to_list=1 ## "Reply-To: This list" by default
mm_forward_auto_discards='True'
mm_bounce_processing='False'

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
    mm_subject_prefix="(${fml_cf[BRACKET]})"
    ;;
  '[]')
    mm_subject_prefix="[${fml_cf[BRACKET]}]"
    ;;
  *)
    perr "$ml_name: SUBJECT_TAG_TYPE='${fml_cf[PERMIT_POST_FROM]}' invalid"
    ;;
  esac
  mm_subject_prefix="$mm_subject_prefix "
fi

mm_include_list_post_header='No'
if [[ ${fml_cf[USE_RFC2369]-1} = 1 ]]; then
  mm_include_list_post_header='True'
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

run "$mm_dir/bin/newlist" \
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
  echo "m.generic_nonmember_action = $mm_generic_nonmember_action"
  echo "m.discard_these_nonmembers = ['''^(${fml_cf[REJECT_ADDR]})@''']"
  echo "m.forward_auto_discards = $mm_forward_auto_discards"
  echo "m.max_message_size = $mm_max_message_size"
  echo "m.max_days_to_hold = $mm_max_days_to_hold"
  echo "m.subject_prefix = '''$mm_subject_prefix'''"
  echo "m.subscribe_policy = $mm_subscribe_policy"
  echo "m.reply_goes_to_list = $mm_reply_goes_to_list"
  echo "m.include_list_post_header = $mm_include_list_post_header"
  echo "m.archive = $mm_archive"
  echo "m.archive_volume_frequency = $mm_archive_volume_frequency"
  echo "m.bounce_processing = $mm_bounce_processing"

  echo "m.owner = ["
  (
    ## Migrate owner addresses from the fml aliases file
    ## FIXME: Support ":include:/path/to/file"-style entries
    ## (1) Remove comments
    ## (2) Normalize separators
    ## (3) Unwrap lines
    ## (4) Append @DOMAINNAME if @ does not exist
    ## (5) Enclode addresses by triple-quotations
    (
      ## Append a blank line after aliases (This is required for sed unwrap script)
      cat "$fml_aliases"
      echo
    ) \
    |sed \
      -e 's/#.*//' \
      -e 's/[ 	,]\{1,\}/ /g' \
    |sed -n \
      -e '1 {h; $ !d}' \
      -e '$ {x; s/\n / /g; p}' \
      -e '/^ / {H; d}' \
      -e '/^ /! {x; s/\n / /g; p}' \
    |grep -i "^$ml_name-admin *:" \
    |sed \
      -e 's/^[^:]*: *//' \
      -e 's/ /\n/g' \
    ;
    sed \
      -e 's/#.*//' \
      -e '/^$/d' \
      members-admin \
      include-admin \
      2>/dev/null \
    ;
  ) \
  |sed \
    -e "s/^fml\$/$mm_site_email/" \
    -e "s/^\([^@]*\)\$/\1@${fml_cf[DOMAINNAME]}/" \
    -e 's/^/"""/' \
    -e 's/$/""",/' \
  |sort -uf \
  ;
  echo ']'

  if [[ -f moderators ]]; then
    echo "m.moderator = ["
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
|run "$mm_dir/bin/withlist" --quiet --lock "$ml_name_lower" \
  || exit 1

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
    ## FIXME: Add a address as a members with --nomail option
    continue
  fi
  if [[ -n $digest ]]; then
    echo "$address" >>"$tmp_dir/$ml_name.digest-members"
  else
    echo "$address" >>"$tmp_dir/$ml_name.regular-members"
  fi
done \

if [[ -s $tmp_dir/$ml_name.regular-members || -s $tmp_dir/$ml_name.digest-members ]]; then
  run "$mm_dir/bin/add_members" \
    --regular-members-file="$tmp_dir/$ml_name.regular-members" \
    --digest-members-file="$tmp_dir/$ml_name.digest-members" \
    --welcome-msg=n \
    --admin-notify=n \
    "$ml_name" \
    || exit 1 \
  ;
fi

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
  |run tee "$mm_mbox.fml" >/dev/null \
  ;

  run chown "$mm_user:" "$mm_mbox.fml"

  if [[ -s $mm_mbox.fml ]]; then
    run "$mm_dir/bin/arch" \
      --quiet \
      --wipe \
      "$ml_name" \
      "$mm_mbox.fml" \
      || exit 1 \
    ;
  fi
fi

## ======================================================================

#mv "$log" "$mm_ml_dir/"

exit 0

