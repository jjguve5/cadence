#!/bin/sh
# Uploads server/ to the FTP host. Credentials come from %USERPROFILE%\.sticky-notes-ftp (never in the repo).
f="$HOME/.sticky-notes-ftp"
get() { grep -E "^$1=" "$f" | head -1 | cut -d= -f2- | tr -d '\r'; }
n="$(mktemp)"
printf 'machine nl1-ss8.a2hosting.com login %s password %s\n' "$(get user)" "$(get pass)" > "$n"
cd "$(dirname "$0")/server"
for p in *.php .htaccess data/.htaccess; do
  curl -sS --ssl-reqd --ftp-create-dirs --netrc-file "$n" -T "$p" "ftp://nl1-ss8.a2hosting.com/cadence/$p" --max-time 60 && echo "uploaded $p"
done
rm -f "$n"
