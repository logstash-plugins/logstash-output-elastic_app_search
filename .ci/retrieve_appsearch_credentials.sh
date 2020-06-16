#!/bin/bash
function wait_for_appsearch {
  local APPSEARCH_URL=${APPSEARCH_URL:-"http://appsearch:3002"}
  local continue=1
  set +e
  while [ $continue -gt 0 ]; do
    curl --connect-timeout 5 --max-time 10 --retry 10 --retry-delay 30 --retry-max-time 120 -s -o /dev/null ${APPSEARCH_URL}/login
    continue=$?
    if [ $continue -gt 0 ]; then
      sleep 1
    fi
  done
}

function load_api_keys {
  local APPSEARCH_USERNAME=${APPSEARCH_USERNAME:-"enterprise_search"}
  local AS_PASSWORD=${AS_PASSWORD:-"password"}
  local APPSEARCH_URL=${APPSEARCH_URL:-"http://appsearch:3002"}
  local SEARCH_URL="${APPSEARCH_URL}/as/credentials/collection?page%5Bcurrent%5D=1"
  echo $(curl -u${APPSEARCH_USERNAME}:${AS_PASSWORD} -s ${SEARCH_URL} | sed -E "s/.*(${1}-[[:alnum:]]{24}).*/\1/")
}

wait_for_appsearch
export APPSEARCH_URL=${APPSEARCH_URL:-"http://appsearch:3002"}
export APPSEARCH_PRIVATE_KEY=`load_api_keys private`
export APPSEARCH_SEARCH_KEY=`load_api_keys search`
unset -f load_api_keys