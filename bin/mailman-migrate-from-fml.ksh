#!/bin/ksh
##
## Mailman 2: Migrate from FML 4.0
## Copyright (c) 2013-2021 SATOH Fumiyas @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##
## WARNING:
##	Cannot migrate the following configuration in a FML config.ph:
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

unset PYTHONPATH
export PYTHONDONTWRITEBYTECODE='set'

cmd_arg0="$0"

function pinfo {
  echo "INFO: $1" 1>&2
}

function pwarn {
  echo "$cmd_arg0: WARNING: $1" 1>&2
}

function perr {
  echo "$cmd_arg0: ERROR: $1" 1>&2
}

function pdie {
  perr "$1"
  exit "${2-1}"
}

function run {
  pinfo "Run command: $*" 1>&2
  if [[ -n ${NO_RUN+set} ]]; then
    [[ -t 0 ]] || cat >/dev/null
  else
    "$@"
  fi
}

function pwgen {
  typeset length="${1-12}"; ${1+shift}
  typeset pw=
  typeset rc

  pw=$(
    tr -dc '#+,.:;<=>_A-Za-z0-9' </dev/urandom 2>/dev/null \
    |tr -d 0DOQ1lI2Z5S6G8B9q \
    |head -c "$length" \
    ;
  )
  [[ -z "$pw" ]] && return 1

  echo "$pw"
}

function fml_true_p {
  [[ ${1-} = @(|0) ]] && return 1
  return 0
}

function fml_clean_lists {
  typeset fname="$1"; shift
  #typeset default_domainname="${1-}"; ${1-shift}

  [[ -s $fname ]] || return 0

  ## FIXME: Append `@$default_domainname` if address has no domainname part
  #|sed "s/^[^@]*\$/&@$default_domainname/" \
  sed -E -n \
    -e '/^#.FML HEADER$/,/#.endFML HEADER$/d' \
    -e 's/^[ \t]+//' \
    -e 's/[ \t]+/ /g' \
    -e '/^[^#]/p' \
    "$fname" \
  |sort -uf \
  ;
}

function fml_size_to_mm_size {
  typeset fml_size="$1"
  typeset -i mm_size

  case "$fml_size" in
  *[Mm])
    ((mm_size = ${fml_size%?} * 1024 * 1024))
    ;;
  *[Kk])
    ((mm_size = ${fml_size%?} * 1024))
    ;;
  esac
  ((mm_size /= 1000))

  echo "$mm_size"
}

## ----------------------------------------------------------------------

_cmds_at_exit=()

cmds_at_exit() {
  typeset cmd

  for cmd in "${_cmds_at_exit[@]}"; do
    "$cmd"
  done
}

trap 'cmds_at_exit' EXIT
for signal in HUP INT TERM; do
  trap 'cmds_at_exit; trap - EXIT '$signal'; kill -'$signal' -$$; exit' $signal
done

## ----------------------------------------------------------------------

_temp_files=()
_cmds_at_exit+=(clean_tempfiles)

create_tempfile() {
  typeset vname="$1"; shift
  typeset fname

  if [[ $vname == *[!_0-9A-Za-z]* ]]; then
    perr "$0: Invalid variable name: $vname"
    return 1
  fi

  fname=$(mktemp "$@" "${TMPDIR:-/tmp}/${0##*/}.XXXXXXXX") || return $?
  _temp_files+=("$fname")
  eval "$vname=\"\$fname\""
}

clean_tempfiles() {
  if type clean_tempfiles_pre >/dev/null 2>&1; then
    clean_tempfiles_pre
  fi
  [[ -n "${_temp_files[0]+set}" ]] && rm -rf "${_temp_files[@]}"
}

create_tempfile tmp_dir -d || pdie "Failed to create temporary directory: $?"

clean_tempfiles_pre() {
  [[ -n $mm_fml_dir ]] || return
  [[ -d $mm_fml_dir ]] || return
  mv "$tmp_dir"/* "$mm_fml_dir/" >/dev/null 2>&1
}

#log="$tmp_dir/${0##*/}.$(date '+%Y%m%d.%H%M%S').log"
#exec 2> >(tee "$log" 1>&2)

mm_user="${MAILMAN_USER-mailman}"
mm_dir="${MAILMAN_DIR-/opt/osstech/lib/mailman}"
mm_var_dir="${MAILMAN_VAR_DIR-/opt/osstech/var/lib/mailman}"
mm_lists_dir="${MAILMAN_LISTS_DIR-$mm_var_dir/lists}"
mm_archives_dir="${MAILMAN_ARCHIVES_DIR-$mm_var_dir/archives}"

mm_info="${MAILMAN_INFO-}"
mm_description="${MAILMAN_DESCRIPTION-}"

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 FML_LIST_DIR FML_ALIASES [MM_LIST_NAME [MM_LIST_DOMAIN]]"
  exit 1
fi

fml_list_dir="$1"; shift
fml_aliases="$1"; shift
typeset -l mm_list_name mm_list_domain
mm_list_name="${1-}"; ${1+shift}
mm_list_domain="${1-}"; ${1+shift}

if [[ $fml_aliases != /* ]]; then
  fml_aliases="$PWD/$fml_aliases"
fi
fml_localname="${fml_list_dir##*/}"

cd "$fml_list_dir" || exit 1
if [[ ! -f config.ph ]]; then
  pdie "FML config.ph file not found"
fi

## ======================================================================

pinfo "Reading FML config.ph file"

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

pinfo "Constructing FML address lists "

## FML posters address list
fml_list_members="$tmp_dir/members.cleaned"
fml_clean_lists members >"$fml_list_members" || exit $?

## FML distribution address list
fml_list_actives="$tmp_dir/actives.cleaned"
fml_list_actives_wo_options="$tmp_dir/actives.cleaned-wo-options"
fml_clean_lists actives >"$fml_list_actives" || exit $?
sed 's/ .*//' "$fml_list_actives" >"$fml_list_actives_wo_options" || exit $?

fml_list_diff="$tmp_dir/diff-members-actives"
diff -i "$fml_list_members" "$fml_list_actives_wo_options" >"$fml_list_diff"

fml_list_only_in_members="$tmp_dir/in-members-only"
sed -n 's/^< //p' "$fml_list_diff" >"$fml_list_only_in_members"

## ======================================================================

pinfo "Constructing Mailman list configuration"

if [[ $mm_list_name == *@* ]]; then
  ## Mailman vhost
  mm_list_domain="${mm_list_name##*@}"
  mm_list_dir="$mm_lists_dir/$mm_list_domain/${mm_list_name%@*}"
  mm_list_mbox="$mm_archives_dir/private/$mm_list_domain/$mm_list_name.mbox/$mm_list_name.mbox"
else
  if [[ -z $mm_list_name ]]; then
    mm_list_name="${fml_cf[MAIL_LIST]%@*}"
  fi
  if [[ -z $mm_list_domain ]]; then
    mm_list_domain="${fml_cf[MAIL_LIST]##*@}"
  fi
  mm_list_dir="$mm_lists_dir/$mm_list_name"
  mm_list_mbox="$mm_archives_dir/private/$mm_list_name.mbox/$mm_list_name.mbox"
fi

if [[ -d $mm_list_dir ]]; then
  pdie "Mailman list $mm_list_name already exists"
fi

mm_owner_email="${MAILMAN_OWNER_EMAIL-mailman@$mm_list_domain}"
mm_postid=$(cat seq 2>/dev/null) && ((mm_postid++))
mm_owner_password=$(pwgen) || pdie "Failed to generate a password" $?
mm_max_message_size=$(fml_size_to_mm_size "${fml_cf[INCOMING_MAIL_SIZE_LIMIT]:-0}")
mm_max_days_to_hold="${fml_cf[MODELATOR_EXPIRE_LIMIT]:-14}"
## &DEFINE_FIELD_FORCED('reply-to',$MAIL_LIST);
## &DEFINE_FIELD_FORCED('Reply-To' , $From_address);
mm_reply_goes_to_list=1 ## "Reply-To: This list" by default
mm_forward_auto_discards='True'
mm_bounce_processing='False'
mm_default_member_moderation='False'

if [[ ${fml_cf[AUTO_REGISTRATION_TYPE]} != 'confirmation' ]]; then
  pdie "$mm_list_name: AUTO_REGISTRATION_TYPE='${fml_cf[AUTO_REGISTRATION_TYPE]}' not supported"
fi

case "${fml_cf[PERMIT_POST_FROM]}" in
anyone)
  mm_member_moderation_action=0 ## Hold for moderated members
  mm_generic_nonmember_action=0 ## Accept for non members
  ;;
members_only)
  case "${fml_cf[REJECT_POST_HANDLER]}" in
  reject)
    mm_member_moderation_action=1 ## Reject for moderated members
    mm_generic_nonmember_action=2 ## Reject for non members
    ;;
  ignore)
    mm_member_moderation_action=2 ## Discard for moderated members
    mm_generic_nonmember_action=3 ## Discard for non members
    ;;
  auto_subscribe)
    pwarn "$mm_list_name: REJECT_POST_HANDLER='${fml_cf[REJECT_POST_HANDLER]}' not supported: Redirect to moderator instead"
    mm_member_moderation_action=0 ## Hold for moderated members
    mm_generic_nonmember_action=1 ## Hold for non members
    ;;
  *)
    perr "$mm_list_name: REJECT_POST_HANDLER='${fml_cf[REJECT_POST_HANDLER]}' not supported"
    ;;
  esac
  ;;
moderator)
  mm_default_member_moderation='True'
  mm_member_moderation_action=0 ## Hold for moderated members
  mm_generic_nonmember_action=1 ## Hold for non members
  ;;
*)
  perr "$mm_list_name: PERMIT_POST_FROM='${fml_cf[PERMIT_POST_FROM]}' not supported"
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
  if [[ ${fml_cf[SUBJECT_FORM_LONG_ID]-} == @(|-1|0) ]]; then
    mm_subject_post_id_fmt="%d"
  else
    mm_subject_post_id_fmt="%0${fml_cf[SUBJECT_FORM_LONG_ID]-5}d"
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
    mm_subject_prefix="(${fml_cf[BRACKET]})"
    ;;
  '[]')
    mm_subject_prefix="[${fml_cf[BRACKET]}]"
    ;;
  *)
    perr "$mm_list_name: SUBJECT_TAG_TYPE='${fml_cf[SUBJECT_TAG_TYPE]}' invalid"
    ;;
  esac
  mm_subject_prefix="$mm_subject_prefix "
fi

mm_include_rfc2369_headers='True'
if [[ ${fml_cf[USE_RFC2369]-1} != 1 ]]; then
  mm_include_rfc2369_headers='False'
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
  --emailhost="$mm_list_domain" \
  "$mm_list_name" \
  "$mm_owner_email" \
  "$mm_owner_password" \
  || exit 1

echo "$mm_owner_password" |run tee "$mm_list_dir/ownerpassword" >/dev/null \
  || exit 1

## ----------------------------------------------------------------------

mm_fml_dir="$mm_list_dir/fml"

run mkdir -m 0750 "$mm_fml_dir" || exit $?
run export PYTHONPATH="$mm_fml_dir" || exit $?
for fname in config.ph seq members{,-admin} actives moderators include-admin; do
  if [[ -f "$fname" ]]; then
    run cp -pn "$fname" "$mm_fml_dir/" || exit $?
  fi
done

## ======================================================================

pinfo "Migrating list configuration to Mailman"

mm_withlist_config_py="$mm_fml_dir/mm_withlist_config.py"

(
  echo 'def run(m):'
  echo "m.info = '''$mm_info'''"
  echo "m.description = '''$mm_description'''"
  echo "m.default_member_moderation = $mm_default_member_moderation"
  echo "m.member_moderation_action = $mm_member_moderation_action"
  echo "m.generic_nonmember_action = $mm_generic_nonmember_action"
  ## FML $REJECT_ADDR does NOT send a reject notice to a poster,
  ## but discards a post and forwards the post to owners.
  ## thus we migrate $REJECT_ADDR to m.discard_these_nonmembers
  ## instead of m.reject_these_nonmembers.
  echo "m.discard_these_nonmembers = ['''^(${fml_cf[REJECT_ADDR]})@''']"
  echo "m.forward_auto_discards = $mm_forward_auto_discards"
  echo "m.max_message_size = $mm_max_message_size"
  echo "m.max_days_to_hold = $mm_max_days_to_hold"
  echo "m.subject_prefix = '''$mm_subject_prefix'''"
  echo "m.subscribe_policy = $mm_subscribe_policy"
  echo "m.reply_goes_to_list = $mm_reply_goes_to_list"
  echo "m.include_rfc2369_headers = $mm_include_rfc2369_headers"
  ## include_list_post_header depends on include_rfc2369_headers
  echo "m.include_list_post_header = True"
  echo "m.archive = $mm_archive"
  echo "m.archive_volume_frequency = $mm_archive_volume_frequency"
  echo "m.bounce_processing = $mm_bounce_processing"

  echo "m.owner = ["
  (
    ## Migrate owner addresses from the FML aliases file
    ## FIXME: Support ":include:/path/to/file"-style entries
    ## (1) Remove comments
    ## (2) Normalize separators
    ## (3) Unwrap lines
    ## (4) Append @DOMAINNAME if @ does not exist
    ## (5) Enclose addresses by triple-quotations
    (
      ## Append a blank line after aliases (This is required for sed unwrap script)
      cat "$fml_aliases" || perr "Failed to read FML aliases file: $fml_aliases"
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
    |grep -i "^$fml_localname-admin *:" \
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
    -e '/^:include:/d' \
    -e "s/^fml\$/$mm_owner_email/" \
    -e "s/^\([^@]*\)\$/\1@${fml_cf[DOMAINNAME]}/" \
    -e 's/^/"""/' \
    -e 's/$/""",/' \
  |sort -uf \
  ;
  echo ']'

  if [[ -f moderators ]]; then
    echo "m.moderator = ["
    fml_clean_lists moderators
    echo ']'
  fi

  if [[ -n $mm_postid ]]; then
    echo "m.post_id = $mm_postid"
  fi

  ## FIXME: Add to members and call mlist.setDeliveryStatus(addr, MemberAdaptor.BYADMIN)
  echo "m.accept_these_nonmembers += ["
  sed -n 's/^.*$/"""&""",/p' "$fml_list_only_in_members"
  echo ']'

  echo 'm.Save()'
) \
|sed '2,$s/^/    /' \
>"$mm_withlist_config_py"

run "$mm_dir/bin/withlist" \
  --run "$(basename "$mm_withlist_config_py" .py).run" \
  --quiet \
  --lock "$mm_list_name" \
  || exit 1

## ======================================================================

## FIXME: Migrate header filter

#header_filter=$(
#  sed -n 's/^ *&*DEFINE_FIELD_PAT_TO_REJECT(.\(.*\)., *.\(.*\).);/\1:.*\2/p' \
#    "$fml_cf_file" \
#    ;
#)

## ======================================================================

pinfo "Convert FML actives data to Mailman members data"

: >"$mm_fml_dir/$fml_localname.regular-members.raw"
: >"$mm_fml_dir/$fml_localname.digest-members.raw"

if [[ -s $fml_list_actives ]]; then
  cat "$fml_list_actives" \
  |while read -r address options; do
    skip=
    digest=
    for option in $options; do
      case "$option" in
      s=skip|s=1)
	skip="set"
	;;
      m=[1-9]*)
	digest="set"
	;;
      esac
    done

    if [[ $address != *@* ]]; then
      address="$address@$mm_list_domain"
    fi
    if [[ -n $skip ]]; then
      echo "$address" >>"$mm_fml_dir/$fml_localname.nomail-members.raw"
    fi
    if [[ -n $digest ]]; then
      echo "$address" >>"$mm_fml_dir/$fml_localname.digest-members.raw"
    else
      echo "$address" >>"$mm_fml_dir/$fml_localname.regular-members.raw"
    fi
  done
fi

for mtype in nomail regular digest; do
  sort -uf \
  <"$mm_fml_dir/$fml_localname.$mtype-members.raw" \
  >"$mm_fml_dir/$fml_localname.$mtype-members" \
  ;
done

## ----------------------------------------------------------------------


if [[ -s $mm_fml_dir/$fml_localname.regular-members || -s $mm_fml_dir/$fml_localname.digest-members ]]; then
  pinfo "Add Mailman members"
  run "$mm_dir/bin/add_members" \
    --regular-members-file="$mm_fml_dir/$fml_localname.regular-members" \
    --digest-members-file="$mm_fml_dir/$fml_localname.digest-members" \
    --welcome-msg=n \
    --admin-notify=n \
    "$mm_list_name" \
    || exit 1 \
  ;

  pinfo "Set nomail options to Mailman members"
  mm_withlist_nomail_py="$mm_fml_dir/mm_withlist_nomail.py"
  (
    echo 'from Mailman import MemberAdaptor'
    echo 'def run(m):'
    sed 's/^/m.setDeliveryStatus("""/; s/$/""", MemberAdaptor.UNKNOWN)/' \
      "$mm_fml_dir/$fml_localname.nomail-members.raw" \
    ;
    echo 'm.Save()'
  ) \
  |sed '3,$s/^/    /' \
  >"$mm_withlist_nomail_py"
  run "$mm_dir/bin/withlist" \
    --run "$(basename "$mm_withlist_nomail_py" .py).run" \
    --quiet \
    --lock "$mm_list_name" \
    || exit $?
fi

## ======================================================================

if [[ -d spool ]] && ls -fF spool |grep '^[1-9][0-9]*$' >/dev/null; then
  pinfo "Migrating list archive to Mailman"

  from_dummy="From dummy  $(LC_ALL=C TZ= date +'%a %b %e %H:%M:%S %Y')"

  ls -fF spool \
  |grep '^[1-9][0-9]*$' \
  |sort -n \
  |while read -r n; do \
    echo "$from_dummy"
    sed 's/^>*From />&/' "spool/$n"
    echo
  done \
  |run tee "$mm_list_mbox.fml" >/dev/null \
  ;

  run chown "$mm_user:" "$mm_list_mbox.fml"

  if [[ -s $mm_list_mbox.fml ]]; then
    run "$mm_dir/bin/arch" \
      --quiet \
      --wipe \
      "$mm_list_name" \
      "$mm_list_mbox.fml" \
      || exit 1 \
    ;
  fi
fi

## ======================================================================

#mv "$log" "$mm_list_dir/"

exit 0
