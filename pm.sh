#!/usr/bin/env bash

# Commandline options. This defines the usage page, and is used to parse cli
# opts & defaults from. The parsing is unforgiving so be precise in your syntax
read -r -d '' usage <<EOF
  -p   [arg] Project ID. If not specified, Project_ID from current directory's .redmine file will be used.
  -v   [arg] Version ID. If not specified, CURRENT_VERSION_ID from current directory's .redmine file will be used.
  -q   [arg] Saved Query ID. Useful for listing issues.
  -a   [arg] Ancestor (or parent) issue ID. Useful for listing issues.
  -c   [arg] Custom filters. Pass true and then provide the custom query as a JSON object string in the first argument after the command. This will be applied as a filter for listing, or as the update attributes when updating tickets. For more info, see https://redmine.org/projects/redmine/wiki/Rest_Issues.
  -f   [arg] Issue output format. Pass "ids" to list only matching issue ticket ID numbers, useful for piping into other commands. Pass "full" for full JSON formatted with jq. Pass "raw" for full JSON unformatted. Pass "short" to exclude the version and created/updated/due dates in the output.
  -z   [arg] Silence status output. Pass true to silence extra output describing what the script is doing, useful for combining with "-f ids" to pipe ticket IDs back into script for another action.
  -h         This page
EOF

# Examples:
# pm -f ids -z true issues 8191 8338 | pm/pm.sh -f summary issues
# pm -c true -f summary issues '{"created_on": ">=2019-10-01", "fixed_version_id": "!249"}'
# pm -c true -f summary -z true issues '{"created_on": "lw"}' | sort
# pm issue open 7784
# pm versions
# pm queries
# pm -v 250 issues

#####################################################################
# PARSE OPTS FUNCTIONS FROM parse_opts.sh
#####################################################################

function help () {
  echo "" 1>&2
  echo " ${@}" 1>&2
  echo "" 1>&2
  echo "  ${usage}" 1>&2
  echo "" 1>&2
  exit 0
}

### Parse commandline options
#####################################################################

# Translate usage string -> getopts arguments, and set $arg_<flag> defaults
while read line; do
  opt="$(echo "${line}" |awk '{print $1}' |sed -e 's#^-##')"
  if ! echo "${line}" |egrep '\[.*\]' >/dev/null 2>&1; then
    init="0" # it's a flag. init with 0
  else
    opt="${opt}:" # add : if opt has arg
    init=""  # it has an arg. init with ""
  fi
  opts="${opts}${opt}"

  varname="arg_${opt:0:1}"
  if ! echo "${line}" |egrep '\. Default=' >/dev/null 2>&1; then
    eval "${varname}=\"${init}\""
  else
    match="$(echo "${line}" |sed 's#^.*Default=\(\)#\1#g')"
    eval "${varname}=\"${match}\""
  fi
done <<< "${usage}"

# Reset in case getopts has been used previously in the shell.
OPTIND=1

# Overwrite $arg_<flag> defaults with the actual CLI options
while getopts "${opts}" opt; do
  line="$(echo "${usage}" |grep "\-${opt}")"


  [ "${opt}" = "?" ] && help "Invalid use of script: ${@} "
  varname="arg_${opt:0:1}"
  default="${!varname}"

  value="${OPTARG}"
  if [ -z "${OPTARG}" ] && [ "${default}" = "0" ]; then
    value="1"
  fi

  eval "${varname}=\"${value}\""
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

### Switches (-h for showing helppage)
#####################################################################

# help mode
if [ "${arg_h}" = "1" ]; then
  # Help exists with code 1
  help "Help using ${0}"
fi

### Runtime
#####################################################################

# Exit on error. Append ||true if you expect an error.
# set -e is safer than #!/bin/bash -e because that is neutralised if
# someone runs your script like `bash yourscript.sh`
set -o errexit
set -o nounset

# Bash will remember & return the highest exitcode in a chain of pipes.
# This way you can catch the error in case mysqldump fails in `mysqldump |gzip`
set -o pipefail

#####################################################################
# END PARSE OPTS FUNCTIONS FROM parse_opts.sh
#####################################################################

JQ_COLORS='
def colors:
{
  "black": "\u001b[30m",
  "red": "\u001b[31m",
  "green": "\u001b[32m",
  "yellow": "\u001b[33m",
  "blue": "\u001b[34m",
  "magenta": "\u001b[35m",
  "cyan": "\u001b[36m",
  "white": "\u001b[37m",
  "reset": "\u001b[0m",
};
'
RESET="\033[0;0m"
ORANGE="\033[0;33m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
LIGHT_PURPLE="\033[1;34m"
WHITE="\033[1;37m"
PURPLE="\033[1;35m"
CYAN="\033[1;36m"
BLUE="\033[0;34m"
LIGHT_GRAY="\033[0;37m"
DARK_GRAY="\033[1;30m"
GRAY="\033[0;90m"
BLACK="\033[0;30m"

function outputProject() {
  decoded="$(echo "${1}" | base64 --decode)"
  echo "$decoded" | jq -r "$JQ_COLORS
  .[] | \"Project: \" + colors.green  + .name + \"\n\" + colors.reset + \
    \"ID: \" + colors.green + \"\(.id)\" + \"\n\" + colors.reset + \
    \"Identifier: \" + colors.green + .identifier + \"\n\" + colors.reset + \
    \"Homepage: \" + colors.green + .homepage + colors.reset"
  }

function getProject() {
  json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/projects/$PROJECT_ID.json")
  outputProject $(echo "$json" | jq -r '[.project] | @base64')
}

function getProjectId() {
  projectName="savant"
  json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/projects.json?limit=$PROJECT_LIMIT")
  outputProject $(echo "$json" | jq -r ".projects | map(select(.identifier==\"$1\")) | @base64")
}

function listQueries() {
  json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/queries.json?limit=$QUERY_LIMIT")
  echo "$json" | jq -r "$JQ_COLORS
  .queries[] | select(.project_id==$PROJECT_ID) | \"\(.id): \" + colors.green + .name + colors.reset"
}

function listIssueStatuses() {
  json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/issue_statuses.json")
  echo "$json" | jq -r "$JQ_COLORS
  .issue_statuses[] | \"\(.id): \" + colors.green + .name + colors.reset"
}

function listIssueCategories() {
  json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/projects/$PROJECT_ID/issue_categories.json")
  echo "$json" | jq -r "$JQ_COLORS
  .issue_categories[] | \"\(.id): \" + colors.green + .name + colors.reset"
}

function listUsers() {
  json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/users.json")
  echo "$json" | jq -r "$JQ_COLORS
  .users[] | \"\(.id): \" + colors.blue + .login + \" \" + colors.green + .firstname + \" \" + .lastname + \" \" + colors.cyan + .mail + colors.reset"
}

function currentUser() {
  json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/users/current.json")
  echo "$json" | jq -r "$JQ_COLORS
  .users | \"\(.id): \" + colors.blue + .login + \" \" + colors.green + .firstname + \" \" + .lastname + \" \" + colors.cyan + .mail + colors.reset"
}

function outputVersions() {
  decoded="$(echo "${1}" | base64 --decode)"
  if [ "${arg_f}" == "ids" ]; then
    echo "$decoded" | jq -r '.[] | .id'
  elif [ "${arg_f}" == "full" ]; then
    echo "$decoded" | jq -r '.'
  elif [ "${arg_f}" == "raw" ]; then
    echo "$decoded"
  else
    echo "$decoded" | jq -r "$JQ_COLORS
    .[] | \"\(.id): \" + \
      colors.red + \"\(.project.name) (\(.project.id)) \" + \
      colors.blue + if .due_date then .due_date else \"----------\" end + \" \" + \
      colors.yellow + .status + colors.reset + \" | \" + \
      colors.green + .name + colors.reset"
  fi
}

function listVersions() {
  json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/projects/$PROJECT_ID/versions.json?limit=$VERSION_LIMIT")
  outputVersions $(echo "$json" | jq -r '.versions | map(select(.status!="closed")) | @base64')
}

function updateVersions() {
  if [ -n "${CUSTOM_FILTERS}" ]; then
    local updateAttributes="$CUSTOM_FILTERS"
  else
    local updateAttributes="{}"
  fi
  updateAttributes=$(echo "$updateAttributes" | jq -r '. | @base64')

  for version in ${PARSED_IDS[@]}; do
    echo -n "Updating $version "
    local body=$(echo "$updateAttributes" | base64 --decode | jq -r '{version: .} | @json')
    local updated=$(curl -s -H "Content-Type: application/json" -X PUT -d "$body" -H "X-Redmine-API-Key: $API_KEY" $DOMAIN/versions/$version.json)
    if [[ "$updated" =~ "errors" ]]; then
      echo -e "\033[0;31m✘ ($updated)\033[0m"
    else
      echo -e "\033[0;32m✔\033[0m"
    fi
  done
}

function outputIssues() {
  # This only happens with passed in issue numbers, so we can count on it being in $2
  [ -z "${1-}" ] && echo -e "${RED}${2}: Issue not found${RESET}" && return
  decoded="$(echo "${1}" | base64 --decode)"
  if [ "${arg_f}" == "ids" ]; then
    echo "$decoded" | jq -r '.[] | .id'
  elif [ "${arg_f}" == "commas" ]; then
    echo "$decoded" | jq -r '.[] | .id' | xargs printf ', %s'  | sed 's/^, //'
  elif [ "${arg_f}" == "full" ]; then
    echo "$decoded" | jq -r '.'
  elif [ "${arg_f}" == "raw" ]; then
    echo "$decoded"
  elif [ "${arg_f}" == "short" ]; then
    echo "$decoded" | jq -r "$JQ_COLORS
    .[] | \"\(.id) > \" + if .parent.id then \"\(.parent.id)\" else \"----\" end + colors.white + \": \" + \
      colors.yellow + .status.name + \
      colors.magenta + \" (\(.done_ratio))\" + colors.white + \" | \" + \
      colors.green + .subject + \
      colors.cyan + \" -\(.author.name)\" + \
      if .assigned_to.name then \" (\(.assigned_to.name))\" else \"\" end + colors.reset"
  else
    echo "$decoded" | jq -r "$JQ_COLORS
    .[] | \"\(.id) > \" + if .parent.id then \"\(.parent.id)\" else \"----\" end + colors.white + \": \" + \
      colors.red + .fixed_version.name + \" \" + \
      colors.blue + (.created_on|strptime(\"%Y-%m-%dT%H:%M:%SZ\")|strftime(\"%Y-%m-%d\")) + \
      \" / \" + (.updated_on|strptime(\"%Y-%m-%dT%H:%M:%SZ\")|strftime(\"%Y-%m-%d\")) + \
      \" / \" + .start_date + \" \" + \
      colors.yellow + .status.name + \
      colors.magenta + \" (\(.done_ratio))\" + colors.white + \" | \" + \
      colors.green + .subject + \
      colors.cyan + \" -\(.author.name)\" + \
      if .assigned_to.name then \" (\(.assigned_to.name))\" else \"\" end + colors.reset"
  fi
}

function openIssues() {
  for issue in ${PARSED_IDS[@]}; do
    open "$DOMAIN/issues/$issue"
  done
}

function listIssues() {
  local useFilters=0
  local filterAttributes=$(echo "{\"limit\": $ISSUE_LIMIT}" | jq -r '. | @base64')

  if [ -n "${arg_q}" ]; then
    [ -z "${arg_z}" ] && echo "From query $arg_q"
    [ -z "${PROJECT_ID}" ] && help "PROJECT_ID must also be set when listing issues by query"
    filterAttributes=$(echo "$filterAttributes" | base64 --decode | jq -r --arg PROJECT_ID "$PROJECT_ID" --arg arg_q "$arg_q" '. + {"project_id": $PROJECT_ID, "query_id": $arg_q} | @base64')
    useFilters=1
  fi

  if [ -n "${arg_v}" ]; then
    [ -z "${arg_z}" ] && echo "From version $arg_v"
    filterAttributes=$(echo "$filterAttributes" | base64 --decode | jq -r --arg arg_v "$arg_v" '. + {"fixed_version_id": $arg_v} | @base64')
    useFilters=1
  fi

  if [ -n "${arg_a}" ]; then
    [ -z "${arg_z}" ] && echo "From parent $arg_a"
    filterAttributes=$(echo "$filterAttributes" | base64 --decode | jq -r --arg arg_a "$arg_a" '. + {"parent_id": $arg_a} | @base64')
    useFilters=1
  fi

  if [ -n "${arg_c}" ]; then
    [ -z "${arg_z}" ] && echo "From custom filters $CUSTOM_FILTERS"
    filterAttributes=$(echo "$filterAttributes" | base64 --decode | jq -r ". + $CUSTOM_FILTERS | @base64")
    useFilters=1
  fi

  if [ "$useFilters" -eq "1" ]; then
    local queryString=$(echo "$filterAttributes" | base64 --decode | jq -r ". | to_entries | map(\"\(.key)=\(.value | @uri)\") | join(\"&\")")
    json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/issues.json?$queryString")
    outputIssues $(echo "$json" | jq -r '.issues | @base64')
  else
    [ -z "${arg_z}" ] && echo "From input IDs"
    for issue in ${PARSED_IDS[@]}; do
      json=$(curl -s -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $API_KEY" "$DOMAIN/issues/$issue.json")
      outputIssues "$(echo "$json" | jq -r '[.issue] | @base64')" "$issue"
    done
  fi
}

function updateIssues() {
  if [ -n "${CUSTOM_FILTERS}" ]; then
    local updateAttributes="$CUSTOM_FILTERS"
  else
    local updateAttributes="{}"
  fi
  updateAttributes=$(echo "$updateAttributes" | jq -r '. | @base64')

  if [ -n "${arg_v}" ]; then
    updateAttributes=$(echo "$updateAttributes" | base64 --decode | jq -r ". + {fixed_version_id: $arg_v} | @base64")
  fi
  if [ -n "${arg_a}" ]; then
    updateAttributes=$(echo "$updateAttributes" | base64 --decode | jq -r ". + {parent_issue_id: $arg_a} | @base64")
  fi

  for issue in ${PARSED_IDS[@]}; do
    echo -n "Updating $issue "
    if [ -n "${arg_a}" ] && [ $issue == $arg_a ]; then
      local body=$(echo "$updateAttributes" | base64 --decode | jq -r '{issue: del(.parent_issue_id)} | @json')
    else
      local body=$(echo "$updateAttributes" | base64 --decode | jq -r '{issue: .} | @json')
    fi
    local updated=$(curl -s -H "Content-Type: application/json" -X PUT -d "$body" -H "X-Redmine-API-Key: $API_KEY" $DOMAIN/issues/$issue.json)
    if [[ "$updated" =~ "errors" ]]; then
      echo -e "\033[0;31m✘ ($updated)\033[0m"
    else
      echo -e "\033[0;32m✔\033[0m"
    fi
  done
}

function parseIDs() {
  for arg in "$@"; do
    id="${arg/[, ]/}"
    PARSED_IDS+=("$id")
  done
}

source .redmine

# Main command as first non-parsed/flagged argument
[ -z "${1-}" ] && echo -e "${RED}No command given${RESET}" && exit 1
cmd=$1
shift

# Get sub-command if present
if [ "${1-}" == "update" ] ||
  [ "${1-}" == "list" ] ||
  [ "${1-}" == "open" ] ||
  [ "${1-}" == "id" ]; then
  cmd2=$1
  shift
fi

ISSUE_LIMIT=250
VERSION_LIMIT=200
QUERY_LIMIT=200
PROJECT_LIMIT=200

declare -a PARSED_IDS

# Override default values from .redmine file
if [ -n "${arg_p}" ]; then
  [ -z "${arg_z}" ] && echo "Overriding PROJECT_ID $PROJECT_ID with $arg_p"
  PROJECT_ID="$arg_p"
fi

if [ -n "${arg_v}" ]; then
  [ -z "${arg_z}" ] && echo "Overriding CURRENT_VERSION_ID $CURRENT_VERSION_ID with $arg_v"
  CURRENT_VERSION_ID="$arg_v"
fi

# This is a weird work-around because the parse_opts.sh script mangles JSON
# values passed into flagged arguments, and I don't have time to debug and
# figure out why.
if [ -n "${arg_c}" ]; then
  CUSTOM_FILTERS="$1"
  shift
fi

# Copy command-line arguments over to new array
ARGS=( $@ )

# Read in from piped input, if present, and append to newly-created array
if [ ! -t 0 ]; then
  declare -a STDIN_ARGS
  while read x; do
    STDIN_ARGS+=("$x")
  done < /dev/stdin
  ARGS=( $@ ${STDIN_ARGS[@]} )
fi

if [ "$cmd" == "project" ]; then
  if [ "${cmd2-}" == "id" ]; then
    [ -z "${arg_z}" ] && echo "Getting project from identifier"
    getProjectId "$1"
  else
    [ -z "${arg_z}" ] && echo "Getting current project"
    getProject
  fi

elif [ "$cmd" == "queries" ]; then
  [ -z "${arg_z}" ] && echo "Getting queries"
  listQueries

elif [ "$cmd" == "statuses" ]; then
  [ -z "${arg_z}" ] && echo "Getting issue statuses"
  listIssueStatuses

elif [ "$cmd" == "categories" ]; then
  [ -z "${arg_z}" ] && echo "Getting issue categories"
  listIssueCategories

elif [ "$cmd" == "users" ]; then
  [ -z "${arg_z}" ] && echo "Getting users"
  listUsers

elif [ "$cmd" == "user" ]; then
  [ -z "${arg_z}" ] && echo "Getting users"
  currentUser

elif [ "$cmd" == "versions" ]; then
  if [ "${cmd2-}" == "update" ]; then
    [ -z "${arg_z}" ] && echo "Updating versions"
    parseIDs "${ARGS[@]-}"
    updateVersions

  else
    [ -z "${arg_z}" ] && echo "Getting versions"
    listVersions
  fi

elif [ "$cmd" == "issue" ]; then
  if [ "${cmd2-}" == "update" ]; then
    [ -z "${arg_z}" ] && echo "Updating issue"
    shift
    parseIDs "$1"
    updateIssues

  elif [ "${cmd2-}" == "open" ]; then
    [ -z "${arg_z}" ] && echo "Opening issue"
    parseIDs "${ARGS[0]-}"
    openIssues

  else
    [ -z "${arg_z}" ] && echo "Getting issue"
    # Optional "list" command, defaults to this anyway
    if [ "${cmd2-}" == "list" ]; then
      shift
    fi
    parseIDs "${ARGS[0]-}"
    listIssues
  fi

elif [ "$cmd" == "issues" ]; then
  if [ "${cmd2-}" == "update" ]; then
    [ -z "${arg_z}" ] && echo "Updating issues"
    parseIDs "${ARGS[@]-}"
    updateIssues

  elif [ "${cmd2-}" == "open" ]; then
    [ -z "${arg_z}" ] && echo "Opening issues"
    parseIDs "${ARGS[@]-}"
    openIssues

  else
    [ -z "${arg_z}" ] && echo "Getting issues"
    parseIDs "${ARGS[@]-}"
    listIssues
  fi
else
  [ -z "${arg_z}" ] && echo -e "${RED}Command $cmd not found${RESET}"
  exit 1
fi
