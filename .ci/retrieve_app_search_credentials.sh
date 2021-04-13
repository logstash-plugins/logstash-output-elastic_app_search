#!/bin/bash
function wait_for_enterprise_search {
  local continue=1
  set +e
  while [ $continue -gt 0 ]; do
    curl --connect-timeout 5 --max-time 10 --retry 10 --retry-delay 30 --retry-max-time 120 -s -o /dev/null ${ENTERPRISE_SEARCH_URL}/login
    continue=$?
    if [ $continue -gt 0 ]; then
      sleep 1
    fi
  done
}

function load_api_keys {
  local CREDENTIALS_URL="${ENTERPRISE_SEARCH_URL}/as/credentials/collection?page%5Bcurrent%5D=1"
  echo $(curl -u${ENTERPRISE_SEARCH_USERNAME}:${ENTERPRISE_SEARCH_PASSWORD} -s ${CREDENTIALS_URL} | sed -E "s/.*(${1}-[[:alnum:]]{24}).*/\1/")
}

export ENTERPRISE_SEARCH_USERNAME=${ENTERPRISE_SEARCH_USERNAME:-"enterprise_search"}
export ENTERPRISE_SEARCH_PASSWORD=${ENTERPRISE_SEARCH_PASSWORD:-"password"}
export ENTERPRISE_SEARCH_URL=${ENTERPRISE_SEARCH_URL:-"http://enterprise_search:3002"}

wait_for_enterprise_search

export APP_SEARCH_PRIVATE_KEY=`load_api_keys private`
export APP_SEARCH_SEARCH_KEY=`load_api_keys search`

unset -f load_api_keys
