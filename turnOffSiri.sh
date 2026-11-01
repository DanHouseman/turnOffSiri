#!/bin/zsh
# Run directly or with zsh, not with sh.
emulate -LR zsh
setopt PIPE_FAIL
script_name="$0"
usage() {
  cat <<HELP
Usage: $script_name [-v] [-on | -off | -restore path-to-file]

Parameters:
  -v                     Print each application's current status, action,
                         and path as it is processed, with colored columns.
  -off                   Turn OFF Siri learning and suggestions for apps
                         in the standard application folders (default).
  -on                    Turn ON Siri learning and suggestions for apps
                         in the standard application folders.
  -restore path-to-file  Restore the two Siri settings from a backup plist.
                         Always print each app's prior status and action.
                         Other preferences are preserved.
  -h, --help             Show this help screen and exit without changes.

Examples:
  $script_name -v
  $script_name -off -v
  $script_name -on -v
  $script_name -restore "/path/to/backup.plist" -v

A Desktop backup is created before changing settings.
Use only one of -on, -off, or -restore. The -v flag is optional.
ON means learning or suggestions are enabled; OFF means both are disabled.
HELP
}
verbose=0
mode=off
explicit_mode=''
restore_file=''
while (( $# )); do
  case "$1" in
    -v) verbose=1; shift ;;
    -on|-off)
      [[ -z "$explicit_mode" ]] || { usage; exit 2; }
      mode="${1#-}"; explicit_mode="$mode"; shift ;;
    -restore)
      [[ -z "$explicit_mode" ]] && (( $# >= 2 )) && [[ "$2" != -* && -n "$2" ]] || { usage; exit 2; }
      mode=restore; explicit_mode=restore; restore_file="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done



# Restoration always shows each application's original status and action.
[[ "$mode" == restore ]] && verbose=1

domain=com.apple.suggestions
keys=(SiriCanLearnFromAppBlacklist AppCanShowSiriSuggestionsBlacklist)
tmp=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/turnOffSiri.XXXXXXXX") || exit 1
trap '/bin/rm -rf -- "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
read_array() {
  local file="$1" key="$2" count kind value
  local -i i
  reply=()
  kind=$(/usr/bin/plutil -type "$key" "$file" 2>/dev/null) || return 0
  [[ "$kind" == array ]] || { print -u2 -- "Invalid array: $key in $file"; return 1; }
  count=$(/usr/bin/plutil -extract "$key" raw -expect array "$file") || return 1
  for (( i=0; i<count; i++ )); do
    value=$(/usr/bin/plutil -extract "$key.$i" raw -expect string "$file") || return 1
    reply+=("$value")
  done
}


load_current() {
  /usr/bin/defaults export "$domain" "$tmp/current.plist" >/dev/null || return 1
  read_array "$tmp/current.plist" "$keys[1]" || return 1
  current_learn=("${reply[@]}")
  read_array "$tmp/current.plist" "$keys[2]" || return 1
  current_suggest=("${reply[@]}")
}
write_arrays() {
  if (( learn != wanted_learn )); then
    /usr/bin/defaults write "$domain" "$keys[1]" -array "${next_learn[@]}" || return 1
  fi
  if (( suggest != wanted_suggest )); then
    /usr/bin/defaults write "$domain" "$keys[2]" -array "${next_suggest[@]}" || return 1
  fi
  return 0
}
# Change just one app's membership while preserving other app entries.
set_membership() {
  local item="$1" blocked="$2" entry
  local -a kept
  kept=()
  for entry in "${reply[@]}"; do
    [[ "$entry" == "$item" ]] || kept+=("$entry")
  done
  (( blocked )) && kept+=("$item")
  reply=("${kept[@]}")
}
row() {
  local name="$1" state="$2" action="$3" app_path="$4" state_color action_color
  (( verbose )) || return 0
  state_color="$green"; [[ "$state" == OFF || "$state" == SKIP ]] && state_color="$red"
  action_color="$red"; [[ "$action" == 'Turning ON' ]] && action_color="$green"
  printf '%s%-32s%s - %s%-7s%s - %s%-14s%s - %s%s%s\n' \
    "$cyan" "$name" "$reset" "$state_color" "$state" "$reset" \
    "$action_color" "$action" "$reset" "$blue" "$app_path" "$reset"
}

load_current || exit 1
if [[ "$mode" == restore ]]; then
  [[ -f "$restore_file" ]] || { print -u2 -- "Backup not found: $restore_file"; exit 1; }
  /usr/bin/plutil -lint "$restore_file" >/dev/null || exit 1
  /bin/cp -- "$restore_file" "$tmp/restore.plist" || exit 1
  read_array "$tmp/restore.plist" "$keys[1]" || exit 1
  saved_learn=("${reply[@]}")
  read_array "$tmp/restore.plist" "$keys[2]" || exit 1
  saved_suggest=("${reply[@]}")
  if ! /usr/bin/plutil -type "$keys[1]" "$tmp/restore.plist" >/dev/null 2>&1 &&
     ! /usr/bin/plutil -type "$keys[2]" "$tmp/restore.plist" >/dev/null 2>&1; then
    print -u2 -- 'Backup contains neither Siri setting; refusing an unrelated plist.'
    exit 1
  fi
  print -- 'Restoring Siri settings from backup'
else
  print -- "Turning $mode Siri settings for all Applications"
fi
backup=$(/usr/bin/mktemp "$HOME/Desktop/siri-settings-$(date +%Y%m%d-%H%M%S)-XXXXXX") || exit 1
/bin/mv -- "$backup" "$backup.plist" || exit 1
backup="$backup.plist"
/bin/cp -- "$tmp/current.plist" "$backup" || exit 1
print -u2 -- "Backup: $backup"
cyan=$'\e[36m'; green=$'\e[32m'; red=$'\e[31m'; blue=$'\e[34m'; reset=$'\e[0m'
if (( verbose )); then
  printf '%-32s - %-7s - %-14s - %s\n' 'APPLICATION' 'CURRENT' 'ACTION' 'APPLICATION PATH'
fi
failed=0
roots=(/Applications /System/Applications /System/Library/CoreServices/Applications)
[[ -d "$HOME/Applications" ]] && roots+=("$HOME/Applications")
while IFS= read -r -d '' app; do
  name="${${app:t}%.app}"
  id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)
  if [[ -z "$id" ]]; then
    row "$name" SKIP 'No bundle ID' "$app"
    continue
  fi
  learn=0; suggest=0
  (( ${current_learn[(Ie)$id]} > 0 )) && learn=1
  (( ${current_suggest[(Ie)$id]} > 0 )) && suggest=1
  state=ON; (( learn && suggest )) && state=OFF
  case "$mode" in
    off) wanted_learn=1; wanted_suggest=1 ;;
    on) wanted_learn=0; wanted_suggest=0 ;;
    restore)
      wanted_learn=0; wanted_suggest=0
      (( ${saved_learn[(Ie)$id]} > 0 )) && wanted_learn=1
      (( ${saved_suggest[(Ie)$id]} > 0 )) && wanted_suggest=1 ;;
  esac
  if (( learn == wanted_learn && suggest == wanted_suggest )); then
    row "$name" "$state" '' "$app"
    continue
  fi
  action='Turning ON'
  (( wanted_learn && wanted_suggest )) && action='Turning OFF'
  reply=("${current_learn[@]}")
  set_membership "$id" "$wanted_learn"
  next_learn=("${reply[@]}")
  reply=("${current_suggest[@]}")
  set_membership "$id" "$wanted_suggest"
  next_suggest=("${reply[@]}")
  if ! write_arrays; then
    failed=1; row "$name" "$state" FAILED "$app"
    load_current || exit 1
    (( verbose )) || print -u2 -- "Failed: $app"
    continue
  fi
  current_learn=("${next_learn[@]}")
  current_suggest=("${next_suggest[@]}")
  # Print immediately after this app is processed, before the next app.
  row "$name" "$state" "$action" "$app"
done < <(/usr/bin/find "${roots[@]}" -type d -name '*.app' -prune -print0)

if [[ "$mode" == restore ]]; then
  # Restore exact lists too, including entries for apps no longer installed.
  for key in "${keys[@]}"; do
    if /usr/bin/plutil -type "$key" "$tmp/restore.plist" >/dev/null 2>&1; then
      values=("${saved_learn[@]}")
      [[ "$key" == "$keys[2]" ]] && values=("${saved_suggest[@]}")
      /usr/bin/defaults write "$domain" "$key" -array "${values[@]}" || failed=1
    elif /usr/bin/defaults read "$domain" "$key" >/dev/null 2>&1; then
      /usr/bin/defaults delete "$domain" "$key" || failed=1
    fi
  done
  expected_learn=("${saved_learn[@]}")
  expected_suggest=("${saved_suggest[@]}")
else
  expected_learn=("${current_learn[@]}")
  expected_suggest=("${current_suggest[@]}")
fi
# Verify once at the end instead of rereading both complete lists per app.
load_current || exit 1
[[ "${(j:\n:)current_learn}" == "${(j:\n:)expected_learn}" &&
   "${(j:\n:)current_suggest}" == "${(j:\n:)expected_suggest}" ]] || failed=1
(( failed )) && print -u2 -- 'Some settings could not be written or verified. The backup is available for recovery.'
exit "$failed"
