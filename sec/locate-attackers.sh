#!/bin/bash
set -euo pipefail

LOG=$(journalctl -u sshguard.service --no-pager -o short-iso)

# 1) Build per-IP stats from "Attack from" lines (count + timestamps)
# 2) Keep unique IP list in first-seen order
readarray -t ips < <(echo "$LOG" \
  | awk '
    /sshguard\[[0-9]+\]: Attack from "/ {
      if (match($0, /Attack from "([0-9.]+)"/, m)) {
        ip=m[1]
        count[ip]++
        if (!seen[ip]++) order[++n]=ip
      }
    }
    END { for (i=1;i<=n;i++) print order[i] }
  ')

total_unique=${#ips[@]}

# Helper: geolocate once
geo() {
  local ip="$1"
  curl -s "https://ipinfo.io/$ip/json" | jq -r '
    "Country:     " + (.country // "N/A") + "\n" +
    "City:        " + (.city // "N/A") + "\n" +
    "Region:      " + (.region // "N/A") + "\n" +
    "TZ:          " + (.timezone // "N/A") + "\n" +
    "Company:     " + (.org // "N/A")
  '
}

# Print per-IP blocks
for ip in "${ips[@]}"; do
  echo "==== $ip ==== <--------------------------"

  # Geo
  geo "$ip"
  echo

  # Count + timestamps
  echo "$LOG" | awk -v ip="$ip" '
    function fmt(ts) {
      gsub(/T/, " ", ts)
      sub(/[+-][0-9]{2}:[0-9]{2}$/, "", ts)
      return ts
    }

    /sshguard\[[0-9]+\]: Attack from "/ {
      ts=fmt($1)
      if (index($0, "Attack from \""ip"\"")>0) {
        c++
        t=t ts "\n"
      }
    }

    /sshguard\[[0-9]+\]: Blocking "/ {
      ts=fmt($1)
      if (match($0, /Blocking "([0-9.]+)\/[0-9]+"/, m) && m[1]==ip) {
        blocks++
        last_block=ts
        blocked_now=1
      }
    }

    /sshguard\[[0-9]+\]: .*: unblocking after / {
      ts=fmt($1)
      if (match($0, /([0-9.]+): unblocking after/, m) && m[1]==ip) {
        unblocks++
        last_unblock=ts
        blocked_now=0
      }
    }

    END {
      printf "Attacks:      %d\n", c+0
      if (c>0) {
        printf "Timestamps:\n"
        printf "%s", t
      }
      printf "Blocks:       %d\n", blocks+0
      printf "Unblocks:     %d\n", unblocks+0
      printf "Last blocked: %s\n", (last_block ? last_block : "never")
      printf "Last unblock: %s\n", (last_unblock ? last_unblock : "never")
      printf "Blocked now:  %s\n", (blocked_now ? "yes" : "no")
    }
  '
  echo
done

echo "=========================="
echo "Total unique attackers: $total_unique"
echo

# Top countries (uses ipinfo; consider caching if this grows)
echo "Top countries:"
for ip in "${ips[@]}"; do
  curl -s "https://ipinfo.io/$ip/json" | jq -r '.country // "N/A"'
done | sort | uniq -c | sort -nr
