#!/bin/zsh
# Started by launchd at 09:00 (or on wake, if the Mac slept through it): runs the Yahoo fetch once, at a
# random time between 09:00 and 12:00 local. A Mac that wakes after 12:00 skips the day. Then publishes
# state/yahoo.json, if the run wrote one, as a single orphan commit on the `yahoo` branch for the worker
# (not `data`: the GitHub jobs force-push that and would overwrite it). The cookie is never published.
set -u
cd "${0:A:h}/.." || exit 1
mkdir -p state
[[ -f state/yahoo_env ]] && source state/yahoo_env  # export TELEGRAM_TOKEN=... / export TELEGRAM_CHAT_ID=...

today=$(date +%F)
marker=state/yahoo_last_run
[[ -f $marker && $(<$marker) == $today ]] && exit 0

start=$(date -j -f '%F %T' "$today 09:00:00" +%s)
end=$(date -j -f '%F %T' "$today 12:00:00" +%s)
now=$(date +%s)
(( now >= end )) && exit 0
(( from = now > start ? now : start ))
(( target = from + RANDOM % (end - from) ))

# Short sleeps, because the clock keeps moving while the Mac is asleep and a long sleep wouldn't notice.
while (( $(date +%s) < target )); do sleep 60; done
(( $(date +%s) >= end )) && exit 0

print -r -- "$today" > $marker
rm -f state/yahoo.json
/Users/shir_shai/code/.flutter-sdk/bin/dart run bin/yahoo_sync.dart --dump state/yahoo_dump || exit 1
[[ -f state/yahoo.json ]] || exit 0

remote=$(git remote get-url origin)
tmp=$(mktemp -d)
cp state/yahoo.json "$tmp/"
git -C "$tmp" init -q -b yahoo
git -C "$tmp" add yahoo.json
git -C "$tmp" -c user.name=rosteriq-bot -c user.email=bot@users.noreply.github.com commit -qm "yahoo $today"
git -C "$tmp" push -qf "$remote" yahoo
rm -rf "$tmp"
