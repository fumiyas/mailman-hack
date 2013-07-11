#!/bin/ksh

set -u
umask 0027

function perr {
  echo "ERROR: $*"
}

function run {
  echo "$*"
  "$@"
}

mm_sbin_dir="/opt/osstech/sbin"
mm_lists_dir="/opt/osstech/var/lib/mailman/lists"
mm_archive_dir="/opt/osstech/var/lib/mailman/archives"

export PATH="$mm_sbin_dir:$(cd "${0%/*}" && pwd):$PATH" || exit 1
unset PYTHONPATH

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 FML_DIR URL_HOST ADMIN_DEFAULT"
  exit 1
fi

fml_dir="$1"; shift
mm_url_host="$1"; shift
mm_admin_default="$1"; shift

typeset -l ml_name_lower

cd "$fml_dir" || exit 1
for ml_name in *; do
  echo

  fml_cf_file="$ml_name/cf"
  [[ -f $fml_cf_file ]] || continue
  echo "Migrating fml $ml_name ..."

  ml_name_lower="$ml_name"
  mm_ml_dir="$mm_lists_dir/$ml_name_lower"
  if [[ -d $mm_ml_dir ]]; then
    echo "Mailman $ml_name already exists"
    continue
  fi

  mm_postid=$(cat "$ml_name/seq" 2>/dev/null) && let mm_postid++
  mm_mbox="$mm_archive_dir/private/$ml_name_lower.mbox/$ml_name_lower.mbox"
  mm_admin_pass=$(printf '%04x%04x%04x%04x' $RANDOM $RANDOM $RANDOM $RANDOM)

  unset fml_cf
  typeset -A fml_cf
  typeset -u cf_name
  sed \
    -e 's/^ *&*DEFINE_FIELD_FORCED(.\(.*\)., *["'"'"']\?\(.*\)["'"'"']\?);/\1 \2/p' \
    "$fml_cf_file" \
  |sed -n '/^[A-Za-z][A-Za-z_\-]*[ 	][ 	]*/p' \
  |while read -r cf_name cf_value; do
    fml_cf[$cf_name]="${cf_value/\$DOMAINNAME/${fml_cf[DOMAINNAME]-}}"
    #echo "fml_cf[$cf_name]='${fml_cf[$cf_name]}'"
  done

  if [[ ${fml_cf[AUTO_REGISTRATION_TYPE]} != 'confirmation' ]]; then
    perr "$ml_name: AUTO_REGISTRATION_TYPE='${fml_cf[AUTO_REGISTRATION_TYPE]}' not supported"
    continue
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
  *)
    perr "$ml_name: PERMIT_POST_FROM='${fml_cf[PERMIT_POST_FROM]}' not supported"
    ;;
  esac

  mm_subject_post_id_f='%d'
  if [[ -n ${fml_cf[SUBJECT_FORM_LONG_ID]-} ]]; then
    mm_subject_post_id_f="%0${fml_cf[SUBJECT_FORM_LONG_ID]}d"
  fi
  mm_subject_prefix=''
  if [[ ${fml_cf[SUBJECT_TAG_TYPE]} ]]; then
    mm_subject_prefix="${fml_cf[SUBJECT_TAG_TYPE]} "
    mm_subject_prefix="${mm_subject_prefix/:/$ml_name:$mm_subject_post_id_f}"
    mm_subject_prefix="${mm_subject_prefix/,/$ml_name:$mm_subject_post_id_f}"
    mm_subject_prefix="${mm_subject_prefix/ID/$mm_subject_post_id_f}"
  fi

  case "${fml_cf[HTML_INDEX_UNIT]-}" in
  infinite)
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
    ## monthly
    mm_archive_volume_frequency=1
    ;;
  esac

  grep -v '^#' "$ml_name/members-admin" 2>/dev/null \
  |head -n 1 \
  |read -r mm_admin \
  ;
  if [[ -z ${mm_admin-} ]]; then
    mm_admin="$mm_admin_default"
  fi

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

  {
    echo "m.real_name = '$ml_name'"
    echo "m.subject_prefix = '$mm_subject_prefix'"
    ## FIXME
    echo "m.subscribe_policy = 3"
    echo "m.generic_nonmember_action = $mm_generic_nonmember_action"
    echo "m.archive_volume_frequency = $mm_archive_volume_frequency"

    echo -n "m.owner += ["
    grep -v '^#' "$ml_name/members-admin" 2>/dev/null \
    |sed -n '2,$s/\(.*\)/"\1",/p'
    ;
    echo ']'

    if [[ -n $mm_postid ]]; then
      echo "m.post_id = $mm_postid"
    fi

    echo 'm.Save()'
  } \
  |tee /dev/stderr \
  |run withlist --quiet --lock "$ml_name_lower" \
  ;

  # FIXME
  #${fml_cf[REPLY-TO]}
  #${fml_cf[REJECT_ADDR]}

  header_filter=$(
    sed -n 's/^ *&*DEFINE_FIELD_PAT_TO_REJECT(.\(.*\)., *.\(.*\).);/\1:.*\2/p' \
      "$fml_cf_file" \
      ;
  )
  ## FIXME: Migrate header filter

  ## FIXME: Compare actives and members
  sed -n '/^[^#]/p;s/^# //p' "$ml_name/actives" \
  |run add_members \
    --regular-members-file=- \
    --welcome-msg=n \
    --admin-notify=n \
    "$ml_name" \
    || exit 1

  ## FIXME: Disable delivery
  #sed -n 's/^# //p' "$ml_name/actives" \
  #|FIXME

  if ls "$ml_name/spool" 2>/dev/null |grep '^[1-9][0-9]*$' >/dev/null; then
    (cd "$ml_name/spool" && packmbox.pl) >"$mm_mbox.fml" \
      || exit 1

    if [[ ${fml_cf[AUTO_HTML_GEN]} -eq 1 && -s $mm_mbox.fml ]]; then
      run arch \
	--quiet \
	--wipe \
	"$ml_name" \
	"$mm_mbox.fml" \
	|| exit 1
    fi
  fi
done

