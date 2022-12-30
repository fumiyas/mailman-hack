#!/bin/bash
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

# shellcheck disable=SC2317
# Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]

set -u
set -o pipefail || exit $?		## bash 3.0+
shopt -s lastpipe || exit $?		## bash 4.2+
umask 0027

unset PYTHONPATH
export PYTHONDONTWRITEBYTECODE='set'

function pinfo {
  echo "INFO: $1" 1>&2
}

function pwarn {
  echo "$0: WARNING: $1" 1>&2
}

function perr {
  echo "$0: ERROR: $1" 1>&2
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

# shellcheck disable=SC2120 # <function> references arguments, but none are ever passed
function pwgen {
  typeset length="${1-12}"; ${1+shift}
  typeset pw=

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
    -e 's/[ \t]+$//' \
    -e 's/[ \t]+/ /g' \
    -e '/^[^#]/p' \
    "$fname" \
  |sort -uf \
  ;
}

function fml_size_to_mm_size {
  typeset fml_size_raw="$1"
  typeset -i fml_size=0
  typeset -i mm_size=0

  case "$fml_size_raw" in
  *[Mm])
    ((fml_size = ${fml_size_raw%?} * 1024 * 1024))
    ;;
  *[Kk])
    ((fml_size = ${fml_size_raw%?} * 1024))
    ;;
  [!0-9])
    pdie "${FUNCNAME[0]}: Invalid \$INCOMING_MAIL_SIZE_LIMIT value in config.ph: $fml_size_raw"
    ;;
  *)
    fml_size="$fml_size_raw"
    ;;
  esac
  ((mm_size = fml_size / 1000))

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

tmp_dir=
create_tempfile tmp_dir -d || pdie "Failed to create temporary directory: $?"

clean_tempfiles_pre() {
  [[ -n ${mm_fml_dir-} ]] || return
  [[ -d $mm_fml_dir ]] || return
  mv "$tmp_dir"/* "$mm_fml_dir/" >/dev/null 2>&1
}

## ======================================================================

#log="$tmp_dir/${0##*/}.$(date '+%Y%m%d.%H%M%S').log"
#exec 2> >(tee "$log" 1>&2)

fml_aliases=""

mm_user="${MAILMAN_USER-mailman}"
mm_dir="${MAILMAN_DIR-/opt/osstech/lib/mailman}"
mm_var_dir="${MAILMAN_VAR_DIR-/opt/osstech/var/lib/mailman}"
mm_lists_dir="${MAILMAN_LISTS_DIR-$mm_var_dir/lists}"
mm_archives_dir="${MAILMAN_ARCHIVES_DIR-$mm_var_dir/archives}"

typeset -l mm_list_name mm_list_domain
mm_list_name=""
mm_list_domain=""
mm_owners=""
mm_info="${MAILMAN_INFO-}"
mm_description="${MAILMAN_DESCRIPTION-}"

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
  --fml-aliases)
    getopts_want_arg "$opt" ${1+"$1"}
    fml_aliases="$1"; shift
    ;;
  --mm-user)
    getopts_want_arg "$opt" ${1+"$1"}
    mm_user="$1"; shift
    ;;
  --mm-dir)
    getopts_want_arg "$opt" ${1+"$1"}
    mm_dir="$1"; shift
    ;;
  --mm-var-dir)
    getopts_want_arg "$opt" ${1+"$1"}
    mm_var_dir="$1"; shift
    ;;
  --mm-list-name)
    getopts_want_arg "$opt" ${1+"$1"}
    mm_list_name="$1"; shift
    ;;
  --mm-list-domain)
    getopts_want_arg "$opt" ${1+"$1"}
    mm_list_domain="$1"; shift
    ;;
  --mm-owners)
    getopts_want_arg "$opt" ${1+"$1"}
    mm_owners="$1"; shift
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

## ----------------------------------------------------------------------

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 FML_LIST_DIR"
  exit 1
fi

fml_list_dir="$1"; shift

fml_localname="${fml_list_dir##*/}"
if [[ -z $fml_aliases ]]; then
  fml_aliases="$fml_list_dir/aliases"
elif [[ $fml_aliases != /* ]]; then
  fml_aliases="$PWD/$fml_aliases"
fi

cd "$fml_list_dir" || exit $?
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

pinfo "Clean and analize FML address list data"

## FML posters address list
fml_list_posters="$tmp_dir/members.cleaned"
fml_clean_lists members >"$fml_list_posters" || exit $?

## FML moderators address list
fml_list_moderators="$tmp_dir/moderators.cleaned"
if [[ -s moderators ]]; then
  fml_clean_lists moderators >"$fml_list_moderators" || exit $?
fi

## FML distribution address list
fml_list_readers="$tmp_dir/actives.cleaned"
fml_list_readers_wo_options="$tmp_dir/actives.cleaned-wo-options"
fml_clean_lists actives >"$fml_list_readers" || exit $?
sed 's/ .*//' "$fml_list_readers" >"$fml_list_readers_wo_options" || exit $?

fml_list_diff="$tmp_dir/diff-members-actives"
diff -i "$fml_list_posters" "$fml_list_readers_wo_options" >"$fml_list_diff"

## ----------------------------------------------------------------------

pinfo "Construct Mailman members data from FML address list"

mm_members_postonly="$tmp_dir/mm_members.postonly"
sed -n 's/^< //p' "$fml_list_diff" >"$mm_members_postonly"
mm_members_readonly="$tmp_dir/mm_members.readonly"
sed -n 's/^> //p' "$fml_list_diff" >"$mm_members_readonly"

mm_members_regular="$tmp_dir/mm_members.regular"
mm_members_regular_raw="$mm_members_regular.raw"
mm_members_digest="$tmp_dir/mm_members.digest"
mm_members_digest_raw="$mm_members_digest.raw"
mm_members_nomail="$tmp_dir/mm_members.nomail"
mm_members_nomail_raw="$mm_members_nomail.raw"

mm_members_raws=("$mm_members_regular_raw" "$mm_members_digest_raw" "$mm_members_nomail_raw")
for mm_members_raw in "${mm_members_raws[@]}"; do
  : >"$mm_members_raw"
done

# shellcheck disable=SC2002 # Useless cat
cat "$fml_list_readers" \
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
    address="$address@$mm_list_domain" ## FIXME: Add default email domain instead of mm_list_domain
  fi
  if [[ -n $skip ]]; then
    echo "$address" >>"$mm_members_nomail_raw"
  fi
  if [[ -n $digest ]]; then
    echo "$address" >>"$mm_members_digest_raw"
  else
    echo "$address" >>"$mm_members_regular_raw"
  fi
done

cat "$mm_members_postonly" >>"$mm_members_regular_raw"

for mm_members_raw in "${mm_members_raws[@]}"; do
  sort -uf \
  <"$mm_members_raw" \
  >"${mm_members_raw%.raw}" \
  ;
done

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

if [[ -n $mm_owners ]]; then
  mm_owners="${mm_owners// /,}"
  mm_owner="${mm_owners%%,*}"
else
  mm_owner="${MAILMAN_OWNER-mailman@$mm_list_domain}"
fi
mm_owner_password=$(pwgen) || pdie "Failed to generate a password" $?
mm_postid=$(cat seq 2>/dev/null) && ((mm_postid++))
mm_max_message_size=$(fml_size_to_mm_size "${fml_cf[INCOMING_MAIL_SIZE_LIMIT]:-0}")
mm_max_days_to_hold="${fml_cf[MODELATOR_EXPIRE_LIMIT]:-14}"
## &DEFINE_FIELD_FORCED('reply-to',$MAIL_LIST);
## &DEFINE_FIELD_FORCED('Reply-To' , $From_address);
mm_reply_goes_to_list=1 ## "Reply-To: This list" by default
mm_forward_auto_discards='True'
mm_bounce_processing='False'
mm_default_member_moderation='False'

case "${fml_cf[PERMIT_POST_FROM]}" in
anyone)
  mm_member_moderation_action=0 ## Hold for moderated members
  mm_generic_nonmember_action=0 ## Accept for non members
  ;;
members_only)
  if [[ -s $mm_members_readonly ]]; then
    mm_default_member_moderation='True'
  fi
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
    pwarn "$mm_list_name: REJECT_POST_HANDLER='${fml_cf[REJECT_POST_HANDLER]}' not supported: Reject instead"
    mm_member_moderation_action=1 ## Reject for moderated members
    mm_generic_nonmember_action=2 ## Reject for non members
    #pwarn "$mm_list_name: REJECT_POST_HANDLER='${fml_cf[REJECT_POST_HANDLER]}' not supported: Redirect to moderator instead"
    #mm_member_moderation_action=0 ## Hold for moderated members
    #mm_generic_nonmember_action=1 ## Hold for non members
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
  "$mm_owner" \
  "$mm_owner_password" \
  || exit $?

echo "$mm_owner_password" |run tee "$mm_list_dir/ownerpassword" >/dev/null \
  || exit $?

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
  echo '# -*- coding: utf-8 -*-'
  echo 'import re'
  echo 'from Mailman import Utils'
  echo 'def run(m):'
  exec > >(sed 's/^/    /')
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
  echo 'for e in m.discard_these_nonmembers:'
  echo '    re.compile(e)'
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

  if [[ -n $mm_postid ]]; then
    echo "m.post_id = $mm_postid"
  fi

  echo "m.owner = ["
  if [[ -n $mm_owners ]]; then
    echo "'''${mm_owners//,/"'''", "'''"}'''"
  else
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
      -e "s/^fml\$/$mm_owner/" \
      -e "s/^\([^@]*\)\$/\1@${fml_cf[DOMAINNAME]}/" \
      -e 's/^/"""/' \
      -e 's/$/""",/' \
    |sort -uf \
    ;
  fi
  echo ']'
  echo 'for a in m.owner:'
  echo '    Utils.ValidateEmail(a)'

  if [[ -s $fml_list_moderators ]]; then
    echo "m.moderator = ["
    sed \
      -e 's/^/"""/' \
      -e 's/$/""",/' \
      "$fml_list_moderators" \
    ;
    echo ']'
    echo 'for a in m.moderator:'
    echo '    Utils.ValidateEmail(a)'
  fi

  echo 'm.Save()'
) \
>"$mm_withlist_config_py" \
|| exit $?

run "$mm_dir/bin/withlist" \
  --run "$(basename "$mm_withlist_config_py" .py).run" \
  --quiet \
  --lock "$mm_list_name" \
  || exit $?

## ======================================================================

## FIXME: Migrate header filter

#header_filter=$(
#  sed -n 's/^ *&*DEFINE_FIELD_PAT_TO_REJECT(.\(.*\)., *.\(.*\).);/\1:.*\2/p' \
#    "$fml_cf_file" \
#    ;
#)

## ======================================================================

if [[ -s $mm_members_regular || -s $mm_members_digest ]]; then
  pinfo "Add Mailman members"
  run "$mm_dir/bin/add_members" \
    --regular-members-file="$mm_members_regular" \
    --digest-members-file="$mm_members_digest" \
    --welcome-msg=n \
    --admin-notify=n \
    "$mm_list_name" \
  |sed "s/^/INFO: add_members: /" \
    || exit $? \
  ;

  pinfo "Set Mailman member options"
  mm_withlist_member_options_py="$mm_fml_dir/mm_withlist_member_options.py"
  (
    echo '# -*- coding: utf-8 -*-'
    echo 'from Mailman import mm_cfg'
    echo 'from Mailman import MemberAdaptor'
    echo 'def run(m):'
    exec > >(sed 's/^/    /')
    sed 's/^/m.setDeliveryStatus("""/; s/$/""", MemberAdaptor.UNKNOWN)/' \
      "$mm_members_nomail" \
    ;
    sed 's/^/m.setDeliveryStatus("""/; s/$/""", MemberAdaptor.BYADMIN)/' \
      "$mm_members_postonly" \
    ;
    if [[ $mm_default_member_moderation == 'True' ]]; then
      sed 's/^/m.setMemberOption("""/; s/$/""", mm_cfg.Moderate, 0)/' \
        "$fml_list_posters" \
      ;
    fi
    echo 'm.Save()'
  ) \
  >"$mm_withlist_member_options_py" \
  || exit $?
  run "$mm_dir/bin/withlist" \
    --run "$(basename "$mm_withlist_member_options_py" .py).run" \
    --quiet \
    --lock "$mm_list_name" \
    || exit $?
fi

## ======================================================================

# shellcheck disable=SC2010 # Don't use ls | grep
if [[ -d spool ]] && ls -fF spool |grep '^[1-9][0-9]*$' >/dev/null; then
  pinfo "Migrating list archive to Mailman"

  from_dummy="From dummy  $(LC_ALL=C TZ= date +'%a %b %e %H:%M:%S %Y')"

  # shellcheck disable=SC2010 # Don't use ls | grep
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
      || exit $? \
    ;
  fi
fi

## ======================================================================

#mv "$log" "$mm_list_dir/"

exit 0
