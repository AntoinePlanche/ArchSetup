#!/usr/bin/env bash
# rofi script mode: Spotlight's Files tab. Searches the everyday folders only
# (not all of ~, which holds Steam/Wine trees that link back to "/").
DIRS=(Documents Downloads Desktop Pictures Videos Music)

if [[ -n ${ROFI_INFO:-} ]]; then
    setsid -f xdg-open "$ROFI_INFO" >/dev/null 2>&1
    exit 0
fi

printf '\0markup-rows\x1ftrue\n'
printf '\0no-custom\x1ftrue\n'

cd "$HOME" || exit 0
icon_for() {
    case "${1,,}" in
        *.jpg|*.jpeg|*.png|*.webp|*.gif|*.heic) echo "thumbnail://$HOME/$1" ;;
        *.pdf)                       echo application-pdf ;;
        *.doc|*.docx|*.odt)          echo x-office-document ;;
        *.xls|*.xlsx|*.ods|*.csv)    echo x-office-spreadsheet ;;
        *.ppt|*.pptx|*.odp)          echo x-office-presentation ;;
        *.zip|*.tar|*.gz|*.7z|*.rar) echo package-x-generic ;;
        *.mp3|*.flac|*.wav|*.ogg)    echo audio-x-generic ;;
        *.mp4|*.mkv|*.webm|*.mov)    echo video-x-generic ;;
        *.sh|*.py|*.js|*.ts|*.rs|*.c|*.java|*.qml|*.lua|*.json) echo text-x-script ;;
        *)                           echo text-x-generic ;;
    esac
}
esc() { local s=${1//&/&amp;}; s=${s//</&lt;}; printf '%s' "${s//>/&gt;}"; }

existing=()
for d in "${DIRS[@]}"; do [[ -d $d ]] && existing+=("$d"); done
find "${existing[@]}" -type f \
    -not -path '*/.*' -not -path '*/target/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' \
    -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2- |
while IFS= read -r rel; do
    name=${rel##*/}
    dir=${rel%/*}
    printf '%s  <span alpha="45%%" size="small">~/%s</span>\0icon\x1f%s\x1fmeta\x1f%s\x1finfo\x1f%s\n' \
        "$(esc "$name")" "$(esc "$dir")" "$(icon_for "$rel")" "$dir" "$HOME/$rel"
done
