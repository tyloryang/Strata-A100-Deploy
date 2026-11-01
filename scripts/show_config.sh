#!/bin/bash
B=/data/qwen-strata
echo "==== config (api_key redacted)"
sed 's/"api_key": *"[^"]*"/"api_key": "<hidden>"/' "$B/Strata/strata-iq3_xxs.json"
echo "==== files"
ls -l "$B"/Strata/strata-iq3_xxs.json*
echo "==== run script"
cat "$B/Strata/run-iq3_xxs.sh"
echo "==== perms"
stat -c '%a %n' "$B/Strata/strata-iq3_xxs.json"
