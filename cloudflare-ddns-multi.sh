#!/bin/sh

app_name="Cloudflare DDNS Multiple Zone/Record Updater"

user_conf_file='.config/cloudflare-ddns-multi/config.json'
system_conf_file='/etc/cloudflare-ddns-multi/config.json'

default_interval_sec=300
min_interval_sec=10
default_cache_timeout_sec=3600
default_interval_after_fail_sec=900
default_cf_api_url='https://api.cloudflare.com/client/v4'

default_enable_ipv4="true"
default_enable_ipv6="false"

ipv4_commands_curl="
curl -sfL4 -m 5 https://api.ipify.org
curl -sfL4 -m 5 https://checkip.amazonaws.com
curl -sfL4 -m 5 https://curlmyip.net
curl -sfL4 -m 5 https://diagnostic.opendns.com/myip
curl -sfL4 -m 5 https://domains.google.com/checkip
curl -sfL4 -m 5 https://echoip.de
curl -sfL4 -m 5 https://eth0.me
curl -sfL4 -m 5 https://icanhazip.com
curl -sfL4 -m 5 https://ident.me
curl -sfL4 -m 5 https://ifconfig.co
curl -sfL4 -m 5 https://ifconfig.io/ip
curl -sfL4 -m 5 https://ifconfig.me
curl -sfL4 -m 5 https://inet-ip.info
curl -sfL4 -m 5 https://ip.tyk.nu
curl -sfL4 -m 5 https://ipaddr.site
curl -sfL4 -m 5 https://ipcalf.com
curl -sfL4 -m 5 https://ipecho.net/plain
curl -sfL4 -m 5 https://ipinfo.io/ip
curl -sfL4 -m 5 https://l2.io/ip
curl -sfL4 -m 5 https://myexternalip.com/raw
curl -sfL4 -m 5 https://wgetip.com
"

ipv6_commands_curl="
curl -sfL6 -m 5 https://api6.ipify.org/
curl -sfL6 -m 5 https://diagnostic.opendns.com/myip
curl -sfL6 -m 5 https://icanhazip.com
curl -sfL6 -m 5 https://ident.me
curl -sfL6 -m 5 https://ifconfig.co
curl -sfL6 -m 5 https://ifconfig.io/ip
curl -sfL6 -m 5 https://echoip.de
curl -sfL6 -m 5 https://ident.me
curl -sfL6 -m 5 https://tnx.nl/ip
curl -sfL6 -m 5 https://wgetip.com
curl -sfL6 -m 5 https://ip.tyk.nu
curl -sfL6 -m 5 https://curlmyip.net
curl -sfL6 -m 5 https://api6.ipify.org
curl -sfL6 -m 5 https://ifconfig.co
curl -sfL6 -m 5 https://curlmyip.net
curl -sfL6 -m 5 https://icanhazip.com
curl -sfL6 -m 5 https://ifconfig.io/ip
"

ipv4_commands_drill="
drill -4 @one.one.one.one CH TXT whoami.cloudflare | grep ^whoami.cloudflare. | awk '{ print \$5 }' | sed -e 's/^\"//' -e 's/\"$//'
drill -4 @ns1.google.com IN TXT o-o.myaddr.l.google.com | grep ^o-o.myaddr.l.google.com. | awk '{ print \$5 }' | sed -e 's/^\"//' -e 's/\"$//'
drill -4 @resolver1.opendns.com IN A myip.opendns.com | grep ^myip.opendns.com. | awk '{ print \$5 }'
"

ipv6_commands_drill="
drill -6 @one.one.one.one CH TXT whoami.cloudflare | grep ^whoami.cloudflare. | awk '{ print \$5 }' | sed -e 's/^\"//' -e 's/\"$//'
drill -6 @ns1.google.com IN TXT o-o.myaddr.l.google.com | grep ^o-o.myaddr.l.google.com. | awk '{ print \$5 }' | sed -e 's/^\"//' -e 's/\"$//'
drill -6 @resolver1.opendns.com IN AAAA myip.opendns.com | grep ^myip.opendns.com. | awk '{ print \$5 }'
"

ipv4_commands_dig="
dig -4 @one.one.one.one CH TXT whoami.cloudflare +short | sed -e 's/^\"//' -e 's/\"$//'
dig -4 @ns1.google.com IN TXT o-o.myaddr.l.google.com +short | sed -e 's/^\"//' -e 's/\"$//'
dig -4 @resolver1.opendns.com IN A myip.opendns.com +short;
"

ipv6_commands_dig="
dig -6 @one.one.one.one CH TXT whoami.cloudflare +short | sed -e 's/^\"//' -e 's/\"$//'
dig -6 @ns1.google.com IN TXT o-o.myaddr.l.google.com +short | sed -e 's/^\"//' -e 's/\"$//'
dig -6 @resolver1.opendns.com IN AAAA myip.opendns.com +short
"

echo() {
  IFS=" $IFS"
  printf '%s\n' "$*"
  IFS=${IFS#?}
}

debug() {
  if [ "$DEBUG" ]; then
    echo "$(date -Iseconds) [debug] $*" >&2
  fi
}

log() {
  echo "$(date -Iseconds) [info ] $*"
}

log_error() {
  echo "$(date -Iseconds) [error] $*" >&2
  run_commands "$on_error" "$*"
}

cf_api() {
  if [ -n "$api_token" ] ; then
    api_result=$(curl -sSL -H 'Accept: application/json' -H 'Content-Type: application/json' -H "Authorization: Bearer $api_token" "$@")
    debug "$api_result" >&2
  elif [ -n "$email" ] && [ -n "$api_key" ]; then
    api_result=$(curl -sSL -H 'Accept: application/json' -H 'Content-Type: application/json' -H "X-Auth-Email: $email" -H "X-Auth-Key: $api_key" "$@")
    debug "$api_result" >&2
  fi
  echo "$api_result"
}

global_ip() {
  unset ips
  echo "$*" | shuf | while IFS= read -r line
  do
    [ -z "$line" ] && continue
    debug "Execute - $line"
    ip0=$(sh -c "$line" | sed -e 's/^\"//' -e 's/"$//')
    if [ -z "$ip0" ]; then
       log_error "Failed to get IP address - $line"
       continue
    fi
    if [ -z "$ips" ]; then
      ips=$ip0
      continue
    fi
    if echo "$ips" | sed 's/,/\n/g' | grep -xq "$ip0"; then
      echo "$ip0"
      unset ips
      return
    fi
    ips="$ips,$ip0"
  done
  unset ips
}

make_dns_name() {
  zone_name="$1"
  record_name="$2"
  if [ -z "$record_name" ] || [ "$record_name" = "$zone_name" ] || [ "$record_name" = "@" ]; then
    echo "$zone_name"
  else
    echo "$record_name.$zone_name"
  fi
}

cleanup() {
  rv=$?
  debug "cleanup"
  trap '' EXIT
  ! echo "$zlen" | grep -qx "[0-9]\+" && exit
  for i in $( seq 0 $((zlen - 1)) ); do
    zone=$(echo "$conf" | jq .zones[$i])
    api_token=$(echo "$zone" | jq -r '.api_token // empty')
    email=$(echo "$zone" | jq -r '.email // empty')
    api_key=$(echo "$zone" | jq -r '.api_key // empty')
    zone_name=$(echo "$zone" | jq -r '.name // empty')
    zone_id=$(echo "$zone" | jq -r '.zone_id // empty')
    if [ -z "$zone_id" ]; then
      debug "cf_api ${cf_api_url}/zones?name=$zone_name"
      zone_id=$(cf_api "${cf_api_url}/zones?name=$zone_name" | jq -r '.result[0].id // empty')
      if [ -z "$zone_id" ]; then
        log_error "Failed to get zone id - $zone_name"
        continue
      fi
    fi
    records=$(echo "$zone" | jq .records)
    rlen=$(echo "$records" | jq length)
    for j in $( seq 0 $((rlen - 1)) ); do
      record=$(echo "$zone" | jq .records[$j])
      record_name=$(echo "$record" | jq -r '.name // empty')
      dns_name=$(make_dns_name "$zone_name" "$record_name")
      types=$(echo "$record" | jq .types)
      remove_on_exit=$(echo "$record" | jq .remove_on_exit)
      if [ "$remove_on_exit" != "true" ]; then
        continue
      fi
      tlen=$(echo "$types" | jq length)
      for k in $( seq 0 $((tlen - 1)) ); do
        type=$(echo "$record" | jq -r ".types[$k] // empty")
	[ -z "${type}" ] && continue
        debug "cf_api ${cf_api_url}/zones/${zone_id}/dns_records?name=${dns_name}&type=${type}"
        c_id=$(cf_api "${cf_api_url}/zones/${zone_id}/dns_records?name=${dns_name}&type=${type}" | jq -r '.result[0].id // empty')
        if [ -z "$c_id" ]; then
          log_error "Failed to get record id - $dns_name $type"
          continue
        fi
        debug "cf_api -X DELETE ${cf_api_url}/zones/${zone_id}/dns_records/${c_id}"
        result=$(cf_api -X DELETE "${cf_api_url}/zones/${zone_id}/dns_records/${c_id}" | jq -r '.success // empty')
        if [ "$result" = "true" ]; then
          log "Removed [ $dns_name $type ]"
          run_commands "$on_remove" "Removed [ $dns_name $type ]"
        else
          log_error "Failed to remove [ $dns_name $type ]"
        fi
      done
    done
  done
  run_commands "$on_exit" "$app_name exiting."
  exit $rv
}

run_commands() {
  [ -z "$1" ] && return
  commands=$1
  message=$(echo "$2" | sed 's/#/\\#/g')
  commands_len=$(echo "$1" | jq 'length')
  [ "$commands_len" -le 0 ] && return
  for commands_i in $( seq 0 $((commands_len - 1)) ); do
    command=$(echo "$commands" | jq -r ".[$commands_i]" | sed "s#%MESSAGE%#$2#g")
    debug "command: $command"
    command="$command 2>&1"
    output=$(timeout "$command_timeout" sh -c "$command")
    [ $? -ne 0 ] && log_error "Faild to run command: $command"
    [ -n "$output" ] && log "Command output: $output"
  done
}

# main

if [ -r "$1" ]; then
  conf_file="$1"
elif [ -r "$user_conf_file" ]; then
  conf_file="$user_conf_file"
elif [ -r "$system_conf_file" ]; then
  conf_file="$system_conf_file"
else
  log_error "No configuration file found. Exiting."
  exit 1
fi
conf=$(jq -c . < $conf_file)

if [ $? -ne 0 ] || [ -z "$conf" ]; then
  log_error "Configuration file $conf_file load failed. Exiting."
  exit 1
fi

# External Commands
command_timeout=$(echo "$conf" | jq -r '.command_timeout // empty')
if ! echo "$command_timeout" | grep -qe '^[0-9][0-9]*$'; then
  command_timeout=30
fi
on_update=$(echo "$conf" | jq -r '.commands.on_update // empty')
on_create=$(echo "$conf" | jq -r '.commands.on_create // empty')
on_remove=$(echo "$conf" | jq -r '.commands.on_remove // empty')
on_address_check=$(echo "$conf" | jq -r '.commands.on_address_check // empty')
on_address_change=$(echo "$conf" | jq -r '.commands.on_address_change // empty')
on_launch=$(echo "$conf" | jq -r '.commands.on_launch // empty')
on_error=$(echo "$conf" | jq -r '.commands.on_error // empty')
on_exit=$(echo "$conf" | jq -r '.commands.on_exit // empty')

run_commands "$on_launch" "$app_name launched."

oneshot=${ONESHOT}
[ -z "$oneshot" ] && oneshot=$(echo "$conf" | jq -r '.oneshot // empty')

interval_sec=$(echo "$conf" | jq -r '.interval_sec // empty')
[ -z "$interval_sec" ] && interval_sec=$default_interval_sec
[ "$interval_sec" -le 0 ] && interval_sec=$min_interval_sec
cache_timeout_sec=$(echo "$conf" | jq -r '.cache_timeout_sec // empty')
[ -z "$cache_timeout_sec" ] && cache_timeout_sec=$default_cache_timeout_sec
interval_after_fail_sec=$(echo "$conf" | jq -r '.interval_after_fail_sec // empty')
[ -z "$interval_after_fail_sec" ] && interval_after_fail_sec=$default_interval_after_fail_sec

cf_api_url=$(echo "$conf" | jq -r '.cf_api_url // empty')
[ -z "$cf_api_url" ] && cf_api_url=$default_cf_api_url

custom_command_get_ipv4_address=$(echo "$conf" | jq -r '.custom_command_get_ipv4_address // empty')
debug "custom_command_get_ipv4_address: $custom_command_get_ipv4_address"
custom_command_get_ipv6_address=$(echo "$conf" | jq -r '.custom_command_get_ipv6_address // empty')
debug "custom_command_get_ipv6_address: $custom_command_get_ipv6_address"

ipv4_command_type=$(echo "$conf" | jq -r '.ipv4_command_type // empty')
[ -z "$ipv4_command_type" ] && ipv4_command_type='curl'
debug "ipv4_command_type: $ipv4_command_type"
if [ "$ipv4_command_type" = 'drill' ]; then
  ipv4_commands=$ipv4_commands_drill
elif [ "$ipv4_command_type" = 'dig' ]; then 
  ipv4_commands=$ipv4_commands_dig
else
  ipv4_commands=$ipv4_commands_curl
fi

ipv6_command_type=$(echo "$conf" | jq -r '.ipv6_command_type // empty')
[ -z "$ipv6_command_type" ] && ipv4_command_type='curl'
debug "ipv6_command_type: $ipv6_command_type"
if [ "$ipv6_command_type" = 'drill' ]; then
  ipv6_commands=$ipv6_commands_drill
elif [ "$ipv4_command_type" = 'dig' ]; then 
  ipv6_commands=$ipv6_commands_dig
else
  ipv6_commands=$ipv6_commands_curl
fi

enable_ipv4=$(echo "$conf" | jq '.enable_ipv4 // empty')
[ -z "$enable_ipv4" ] && enable_ipv4=$default_enable_ipv4
enable_ipv6=$(echo "$conf" | jq '.enable_ipv6 // empty')
[ -z "$enable_ipv6" ] && enable_ipv6=$default_enable_ipv6

if [ "$enable_ipv4" != "true" ] && [ "$enable_ipv6" != "true" ]; then
  log_error "Both IPv4 and IPv6 disabled. Exiting."
  exit 1
fi

zlen=$(echo "$conf" | jq '.zones | length')
if [ "$zlen" -lt 0 ]; then
  log_error "No Zones specified. Exiting."
  exit 1
fi

trap cleanup INT QUIT TERM PIPE EXIT

while true; do
  log "Start the process."
  if [ "$enable_ipv4" = "true" ]; then
    if [ -n "$custom_command_get_ipv4_address" ]; then
      global_ipv4=$(eval "$custom_command_get_ipv4_address")
    else
      global_ipv4=$(global_ip "$ipv4_commands")
    fi
    if ! echo "$global_ipv4" | grep -qe '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$'; then
      log_error "Failed to get the global IPv4 address."
      unset global_ipv4
    else
      log "Currnet global IPv4 address: $global_ipv4"
    fi
  fi
  if [ "$enable_ipv6" = "true" ]; then
    if [ -n "$custom_command_get_ipv6_address" ]; then
      global_ipv6=$(eval "$custom_command_get_ipv6_address")
    else
      global_ipv6=$(global_ip "$ipv6_commands")
    fi
    if ! echo "$global_ipv6" | grep -qe '^[0-9a-fA-F][0-9a-fA-F:]*[0-9a-fA-F]$'; then
      log_error "Failed to get the global IPv6 address."
      unset global_ipv6
    else
      log "Currnet global IPv6 address: $global_ipv6"
    fi
  fi

  run_commands "$on_address_check" "Global IP address checked: [ IPv4: $global_ipv4 ] [ IPv6: $global_ipv6 ]"

  if [ "$IP_CHECK_ONLY" ]; then
    trap '' EXIT
    exit
  fi

  if [ -z "$global_ipv4" ] && [ -z "$global_ipv6" ]; then
    log_error "Failed to get both global IPv4 and IPv6 addresses. Sleeping for $interval_sec seconds."
    sleep "$interval_sec"
    continue
  fi

  if [ -n "$global_ipv4" ] && [ -n "$pre_global_ipv4" ] && [ "$global_ipv4" != "$pre_global_ipv4" ]; then
    log "Global IPv4 address changed $pre_global_ipv4 -> $global_ipv4"
    run_commands "$on_address_change" "Global IPv4 address changed $pre_global_ipv4 -> $global_ipv4"
  fi
  pre_global_ipv4=$global_ipv4

  if [ -n "$global_ipv6" ] && [ -n "$pre_global_ipv6" ] && [ "$global_ipv6" != "$pre_global_ipv6" ]; then
    log "Global IPv6 address changed $pre_global_ipv6 -> $global_ipv6"
    run_commands "$on_address_change" "Global IPv6 address changed $pre_global_ipv6 -> $global_ipv6"
  fi
  pre_global_ipv6=$global_ipv6

  for i in $( seq 0 $((zlen - 1)) ); do
    zone=$(echo "$conf" | jq .zones[$i])

    zone_name=$(echo "$zone" | jq -r '.name // empty')
    debug "zone_name: $zone_name"
    if [ -z "$zone_name" ]; then
      log_error "No zone name."
      continue
    fi

    api_token=$(echo "$zone" | jq -r '.api_token // empty')
    debug "api_token: $api_token"
    email=$(echo "$zone" | jq -r '.email // empty')
    debug "email: $email"
    api_key=$(echo "$zone" | jq -r '.api_key // empty')
    debug "api_key: $api_key"

    if [ -z "$api_token" ]; then
      if [ -z "$email" ] || [ -z "$api_key" ]; then
        log_error "No api_token or ( email and api_key )."
        continue
      fi
    fi

    zone_id=$(echo "$zone" | jq -r '.zone_id // empty')
    debug "zone_id: $zone_id"
    zone_id_cached_on=$(echo "$zone" | jq -r '.cached_on // empty')
    [ -z "$zone_id_cached_on" ] && zone_id_cached_on=0
    debug "zone_id_cached_on: $zone_id_cached_on"
    debug "now: $(date +%s)"
    left_sec=$(( zone_id_cached_on + cache_timeout_sec - $(date +%s) ))
    debug "left_sec: $left_sec"
    if [ -z "$zone_id" ] || [ "$left_sec" -lt 0 ]; then
      debug "retriving zone_id"
      debug "cf_api ${cf_api_url}/zones?name=$zone_name"
      zone_id=$(cf_api "${cf_api_url}/zones?name=$zone_name" | jq -r '.result[0].id // empty')
      if [ -z "$zone_id" ]; then
        log_error "Failed to get zone_id."
        continue
      fi
      conf=$(echo "$conf" | jq ".zones[$i].zone_id = \"$zone_id\"")
      conf=$(echo "$conf" | jq ".zones[$i].cached_on = $(date +%s)")
    else
      debug "using cached zone_id (cache will timeout in $left_sec seconds)"
    fi
    debug "zone_id: $zone_id"

    records=$(echo "$zone" | jq .records)
    rlen=$(echo "$records" | jq length)
    debug "rlen: $rlen"
    for j in $( seq 0 $((rlen - 1)) ); do
      debug "record: $j"
      record=$(echo "$zone" | jq .records[$j])
      record_name=$(echo "$record" | jq -r '.name // empty')
      debug "record_name: $record_name"
      dns_name=$(make_dns_name "$zone_name" "$record_name")
      debug "dns_name: $dns_name"

      types=$(echo "$record" | jq .types)
      debug "types: $types"

      proxied=$(echo "$record" | jq .proxied)
      [ "$proxied" != "true" ] && [ "$proxied" != "false" ] && proxied=false
      debug "proxied: $proxied"

      create=$(echo "$record" | jq .create)
      debug "create: $create"

      ttl=$(echo "$record" | jq .ttl)
      if ! echo "$ttl" | grep -qe '^[0-9][0-9]*$'; then
        ttl=1
      fi
      debug "ttl: $ttl"

      fixed_ipv4=$(echo "$record" | jq -r '.fixed_ipv4 // empty')
      fixed_ipv6=$(echo "$record" | jq -r '.fixed_ipv6 // empty')
      command_ipv4=$(echo "$record" | jq -r '.command_ipv4 // empty')
      debug "command_ipv4: $command_ipv4"
      [ -n "$command_ipv4" ] && fixed_ipv4=$(eval "$command_ipv4")
      command_ipv6=$(echo "$record" | jq -r '.command_ipv6 // empty')
      debug "command_ipv6: $command_ipv6"
      [ -n "$command_ipv6" ] && fixed_ipv6=$(eval "$command_ipv6")
      debug "fixed_ipv4: $fixed_ipv4"
      debug "fixed_ipv6: $fixed_ipv6"

      tlen=$(echo "$types" | jq length)
      debug "tlen: $tlen"
      for k in $( seq 0 $((tlen - 1)) ); do
        type=$(echo "$record" | jq -r ".types[$k] // empty")

        failed_on=$(echo "$record" | jq -r ".statuses[$k].failed_on // empty")
        [ -z "$failed_on" ] && failed_on=0
        debug "failed_on: $failed_on"
        debug "now: $(date +%s)"
        left_sec=$(( failed_on + interval_after_fail_sec - $(date +%s) ))
        debug "left_sec: $left_sec"
        [ -z "$failed_on" ] && failed_on=0
        if [ -n "$failed_on" ] && [ "$left_sec" -gt 0 ]; then
          log "$dns_name $type - waiting for interval after failure ($left_sec seconds left)"
          continue
        fi

        if [ "$type" = "A" ]; then
          if [ -n "$fixed_ipv4" ]; then
            content=$fixed_ipv4
          elif [ -n "$global_ipv4" ]; then
            content=$global_ipv4
          else
            log_error "No global IPv4 address for $dns_name A record."
            continue
          fi
        elif [ "$type" = "AAAA" ]; then
          if [ -n "$fixed_ipv6" ]; then
            content=$fixed_ipv6
          elif [ -n "$global_ipv6" ]; then
            content=$global_ipv6
          else
            log_error "No global IPv6 address for $dns_name AAAA record."
            continue
          fi
        else
          log_error "Unknown Record Type $type"
          continue
        fi

        cached_on=$(echo "$record" | jq -r ".statuses[$k].cached_on // empty")
        [ -z "$cached_on" ] && cached_on=0
        debug "cached_on: $cached_on"
        debug "now: $(date +%s)"
        left_sec=$(( cached_on + cache_timeout_sec - $(date +%s) ))
        debug "left_sec: $left_sec"

        if [ "$left_sec" -gt 0 ]; then
          debug "check cached content"
          cached_content=$(echo "$record" | jq -r ".contents[$k] // empty")
          if [ "$content" = "$cached_content" ]; then
            log "Cached [$dns_name $type $content ttl:$ttl proxied:$proxied ] ($left_sec seconds left)"
            continue
          fi
        fi

        unset c_id c_ip c_proxied c_ttl
        debug "read record data from CloudFlare"
        if [ "$type" = "A" ]; then
          debug "cf_api ${cf_api_url}/zones/${zone_id}/dns_records?name=${dns_name}&type=A"
          c_record=$(cf_api "${cf_api_url}/zones/${zone_id}/dns_records?name=${dns_name}&type=A" | jq '.result[0]')
        elif [ "$type" = "AAAA" ]; then
          debug "cf_api ${cf_api_url}/zones/${zone_id}/dns_records?name=${dns_name}&type=AAAA"
          c_record=$(cf_api "${cf_api_url}/zones/${zone_id}/dns_records?name=${dns_name}&type=AAAA" | jq '.result[0]')
        fi
        debug "$c_record"
        c_id=$(echo "$c_record" | jq -r '.id // empty')

        # create
        if [ -z "$c_id" ]; then
          if [ "$create" = "true" ]; then
            debug "cf_api -X POST -d \"{ \"type\":\"${type}\",\"name\":\"${dns_name}\",\"content\":\"${content}\",\"ttl\":${ttl},\"proxied\":${proxied} }\" \"${cf_api_url}/zones/${zone_id}/dns_records\""
            result=$(cf_api -X POST -d "{ \"type\":\"${type}\",\"name\":\"${dns_name}\",\"content\":\"${content}\",\"ttl\":${ttl},\"proxied\":${proxied} }" \
                     "${cf_api_url}/zones/${zone_id}/dns_records" | jq -r '.success // empty')
            if [ "$result" = "true" ]; then
              conf=$(echo "$conf" | jq ".zones[$i].records[$j].statuses[$k].cached_on = $(date +%s) | .zones[$i].records[$j].contents[$k] = \"${content}\"")
              log "Created [ $dns_name $type $content ttl:$ttl proxied:$proxied ]"
              run_commands "$on_create" "Created [ $dns_name $type $content ttl:$ttl proxied:$proxied ]"
            else
              conf=$(echo "$conf" | jq ".zones[$i].records[$j].statuses[$k].failed_on = $(date +%s) | del(.zones[$i].records[$j].contents[$k])")
              log_error "Failed to create"
            fi
            continue
          else
            log "$dns_name $type not found. Skipping."
            continue
          fi
        fi

        c_ip=$(echo "$c_record" | jq -r '.content // empty')
        c_proxied=$(echo "$c_record" | jq '.proxied')
        c_ttl=$(echo "$c_record" | jq '.ttl')
        debug "c_ip: $c_ip"
        debug "c_proxied: $c_proxied"
        debug "c_ttl: $c_ttl"

        if [ "$content" = "$c_ip" ] && [ "$proxied" = "$c_proxied" ] && [ "$ttl" = "$c_ttl" ]; then
          conf=$(echo "$conf" | jq ".zones[$i].records[$j].statuses[$k].cached_on = $(date +%s) | .zones[$i].records[$j].contents[$k] = \"${content}\"")
          log "Exists [ $dns_name $type $content ttl:$ttl proxied:$proxied ]"
          continue
        fi

        #update
        debug "cf_api -X PATCH -d \"{ \"type\":\"${type}\",\"name\":\"${dns_name}\",\"content\":\"${content}\",\"ttl\":${ttl},\"proxied\":${proxied} }\" \"${cf_api_url}/zones/${zone_id}/dns_records/${c_id}\" "
        result=$(cf_api -X PATCH -d "{ \"type\":\"${type}\",\"name\":\"${dns_name}\",\"content\":\"${content}\",\"ttl\":${ttl},\"proxied\":${proxied} }" \
                 "${cf_api_url}/zones/${zone_id}/dns_records/${c_id}" | jq -r '.success // empty')
        if [ "$result" = "true" ]; then
          conf=$(echo "$conf" | jq ".zones[$i].records[$j].statuses[$k].cached_on = $(date +%s) | .zones[$i].records[$j].contents[$k] = \"${content}\"")
          log "Updated [ $dns_name $type $content ttl:$ttl proxied:$proxied ]"
          run_commands "$on_update" "Updated [ $dns_name $type $content ttl:$ttl proxied:$proxied ]"
        else
          conf=$(echo "$conf" | jq ".zones[$i].records[$j].statuses[$k].failed_on = $(date +%s) | del(.zones[$i].records[$j].contents[$k])")
          log_error "Failed to update [ $dns_name $type $content ttl:$ttl proxied:$proxied ]"
        fi
      done
    done
  done
  [ "$DEBUG" ] && echo "$conf" | jq .
  if [ -n "$oneshot" ]; then
    log "The process has been completed. Exiting."
    exit 0
  fi
  log "The process has been completed. Sleep for $interval_sec seconds."
  sleep $interval_sec
done
