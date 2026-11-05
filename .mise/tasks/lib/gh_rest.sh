#!/usr/bin/env bash
# Sourced, not run. GraphQL-less `gh`: cloud sessions get a 403 on every
# GraphQL call ("not available from Claude Code sessions"), which kills
# `gh issue view/list/comment/...`. This file holds
#   gh_graphql_down        — cheap, cached verdict "GraphQL is unreachable"
#   gh_rest_dispatch ARGS  — the `gh issue ...` subset re-expressed as REST
# Callers set REAL to the real gh binary (default: gh on PATH) and may set
# STDIN_FILE to a file holding buffered stdin. Contract and limits:
# docs/domain/issue-workflow.md → Cloud sessions.
# Needs only gh and jq. Output imitates gh's non-tty format (tab-separated list,
# compact --json); anything without a REST equivalent exits 2 with one line.

GH_REST_MSG="GraphQL is unavailable in a cloud session"

# Verdict cache: a marker per session, fresh for 30 min. Only a definitive
# answer is cached; a probe that fails for any other reason counts as "up".
gh_graphql_down() {
  case "${GH_SHIM_REST:-}" in 1) return 0 ;; 0) return 1 ;; esac
  [ -n "${CLAUDE_CODE_REMOTE:-}" ] || return 1
  local real=${REAL:-gh} key marker
  key=${CLAUDE_CODE_REMOTE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-default}}
  marker="${TMPDIR:-/tmp}/gh-graphql-$(id -u)-${key//[^A-Za-z0-9_-]/_}"
  if [ -n "$(find "$marker" -mmin -30 2>/dev/null)" ]; then
    [ "$(cat "$marker")" = down ]; return
  fi
  local err
  err=$(GH_SHIM_DEPTH=1 "$real" api graphql -f query='{viewer{login}}' 2>&1 >/dev/null </dev/null); local rc=$?
  if [ "$rc" -eq 0 ]; then echo up >"$marker" 2>/dev/null; return 1; fi
  if grep -qi 'not available from Claude Code' <<<"$err"; then echo down >"$marker" 2>/dev/null; return 0; fi
  return 1
}

# ---- helpers ----------------------------------------------------------------
_rest_die() { echo "gh (REST mode): $*" >&2; exit 2; }
_rest_gql_only() { _rest_die "$* is GraphQL-only; $GH_REST_MSG (needs a local session, or GH_SHIM_REST=0 to retry)"; }
_rest_api() { "${REAL:-gh}" api "$@"; }

_rest_repo() {
  if [ -z "${REST_REPO:-}" ]; then
    local url
    url=$(git remote get-url origin 2>/dev/null) || _rest_die "no git remote 'origin' and no -R OWNER/REPO"
    REST_REPO=$(sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/+$##' <<<"$url")
  fi
}

# _rest_num <arg> — "#12", "12" or an issue URL -> 12.
_rest_num() {
  local n=${1#\#}; n=${n##*/}
  [[ "$n" =~ ^[0-9]+$ ]] || _rest_die "not an issue number: $1"
  echo "$n"
}

# Flag parsing. _rest_flag <argv-index-var>... is awkward in bash, so each verb
# loops `while [ $# -gt 0 ]` and uses these two: _take sets VAL from `--f=v`
# or the next word and sets SHIFT to the words consumed.
_take() {
  if [[ "$1" == *=* ]]; then VAL=${1#*=}; SHIFT=1
  else [ $# -ge 2 ] || _rest_die "flag ${1} needs a value"; VAL=$2; SHIFT=2; fi
}

_rest_body() { # _rest_body <file> -> body text on stdout ("-" reads buffered stdin)
  if [ "$1" = - ]; then if [ -n "${STDIN_FILE:-}" ]; then cat "$STDIN_FILE"; else cat; fi
  else cat "$1" || _rest_die "cannot read $1"; fi
}

# REST issue -> gh's JSON shape (the fields a headless caller asks for).
_REST_ISSUE_JQ='{
  number, title, body: (.body // ""), url: .html_url, id: .node_id,
  state: (.state | ascii_upcase),
  stateReason: ((.state_reason // "") | ascii_upcase),
  author: {login: .user.login},
  labels: [.labels[] | {name, color, description}],
  assignees: [.assignees[] | {login}],
  milestone: (if .milestone then {number: .milestone.number, title: .milestone.title, description: .milestone.description, dueOn: .milestone.due_on} else null end),
  createdAt: .created_at, updatedAt: .updated_at, closedAt: .closed_at,
  isPinned: false
}'
_REST_COMMENT_JQ='{id: .node_id, url: .html_url, body, createdAt: .created_at, author: {login: .user.login}, authorAssociation: .author_association}'
_REST_FIELDS="number title body url id state stateReason author labels assignees milestone createdAt updatedAt closedAt comments"

# _rest_check_fields <csv> — refuse JSON fields REST cannot fill.
_rest_check_fields() {
  local f
  IFS=, read -ra fs <<<"$1"
  for f in "${fs[@]}"; do
    [[ " $_REST_FIELDS " == *" $f "* ]] || _rest_gql_only "--json field '$f'"
  done
}

_rest_emit_json() { # stdin: JSON value; applies --jq if set, else compact
  if [ -n "${JQ_EXPR:-}" ]; then jq -r "$JQ_EXPR"; else jq -c .; fi
}

# ---- issue view -------------------------------------------------------------
_rest_view() {
  local num="" comments=0 fields="" JQ_EXPR=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|--comments) comments=1; shift ;;
      --json|--json=*) _take "$@"; fields=$VAL; shift "$SHIFT" ;;
      -q|--jq|--jq=*) _take "$@"; JQ_EXPR=$VAL; shift "$SHIFT" ;;
      -R|--repo|--repo=*) _take "$@"; REST_REPO=$VAL; shift "$SHIFT" ;;
      -w|--web|-t|--template|--template=*) _rest_die "issue view $1 is not supported in REST mode" ;;
      -*) _rest_die "issue view: unsupported flag $1" ;;
      *) [ -z "$num" ] || _rest_die "issue view: one issue at a time"; num=$(_rest_num "$1") || exit $?; shift ;;
    esac
  done
  [ -n "$num" ] || _rest_die "issue view needs an issue number (no branch inference)"
  [ -z "$fields" ] || _rest_check_fields "$fields"
  _rest_repo
  local issue cj="[]"
  issue=$(_rest_api "repos/$REST_REPO/issues/$num") || exit $?
  if [ "$comments" = 1 ] || [[ ",$fields," == *,comments,* ]]; then
    cj=$(_rest_api --paginate "repos/$REST_REPO/issues/$num/comments?per_page=100" | jq -s "[.[][] | $_REST_COMMENT_JQ]") || exit $?
  fi
  local shaped
  shaped=$(jq -c --argjson c "$cj" "$_REST_ISSUE_JQ + {comments: \$c}" <<<"$issue")
  if [ -n "$fields" ]; then
    jq -c --arg f "$fields" '. as $i | ($f | split(",")) as $k | reduce $k[] as $x ({}; .[$x] = $i[$x])' <<<"$shaped" | _rest_emit_json
    return
  fi
  # Human format, close to `gh issue view` on a non-tty.
  jq -r --argjson withc "$comments" '
    def lab: [.labels[].name] | join(", ");
    "title:\t\(.title)\nstate:\t\(.state)\(if .stateReason != "" then " (" + .stateReason + ")" else "" end)\nauthor:\t\(.author.login)\nlabels:\t\(lab)\nmilestone:\t\(.milestone.title // "")\nnumber:\t\(.number)\nurl:\t\(.url)\n--\n\(.body)" +
    (if $withc == 1 then "\n" + ([.comments[] | "--\nauthor:\t\(.author.login)\ndate:\t\(.createdAt)\n--\n\(.body)"] | join("\n")) else "" end)
  ' <<<"$shaped"
}

# ---- issue list -------------------------------------------------------------
_rest_list() {
  local state=open labels="" assignee="" author="" limit=30 fields="" JQ_EXPR=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -s|--state|--state=*) _take "$@"; state=$VAL; shift "$SHIFT" ;;
      -l|--label|--label=*) _take "$@"; labels=${labels:+$labels,}$VAL; shift "$SHIFT" ;;
      -L|--limit|--limit=*) _take "$@"; limit=$VAL; shift "$SHIFT" ;;
      -a|--assignee|--assignee=*) _take "$@"; assignee=$VAL; shift "$SHIFT" ;;
      -A|--author|--author=*) _take "$@"; author=$VAL; shift "$SHIFT" ;;
      --json|--json=*) _take "$@"; fields=$VAL; shift "$SHIFT" ;;
      -q|--jq|--jq=*) _take "$@"; JQ_EXPR=$VAL; shift "$SHIFT" ;;
      -R|--repo|--repo=*) _take "$@"; REST_REPO=$VAL; shift "$SHIFT" ;;
      -S|--search|--search=*) _rest_die "issue list --search is not supported in REST mode (use --label/--state, or gh api search/issues)" ;;
      -m|--milestone|--milestone=*|--mention|--mention=*|-w|--web|-t|--template) _rest_die "issue list $1 is not supported in REST mode" ;;
      *) _rest_die "issue list: unsupported argument $1" ;;
    esac
  done
  case "$state" in open|closed|all) ;; *) _rest_die "issue list: bad --state $state" ;; esac
  [[ "$limit" =~ ^[0-9]+$ ]] || _rest_die "issue list: bad --limit $limit"
  [ -z "$fields" ] || _rest_check_fields "$fields"
  [[ ",$fields," != *,comments,* ]] || _rest_gql_only "issue list --json comments"
  _rest_repo
  local q="state=$state&per_page=100" page=1 have=0 acc pg
  [ -z "$labels" ] || q+="&labels=$(jq -rn --arg v "$labels" '$v|@uri')"
  [ -z "$assignee" ] || q+="&assignee=$assignee"
  [ -z "$author" ] || q+="&creator=$author"
  acc=$(mktemp); pg=$(mktemp); : >"$acc"
  # Pages go to files, never argv. The endpoint also returns PRs, so a page
  # can yield fewer rows than it holds; stop on an empty page.
  while [ "$have" -lt "$limit" ] && [ "$page" -le 30 ]; do
    _rest_api "repos/$REST_REPO/issues?$q&page=$page" >"$pg" || { rm -f "$acc" "$pg"; exit 1; }
    [ "$(jq length "$pg")" -gt 0 ] || break
    jq -c '.[] | select(has("pull_request") | not)' "$pg" >>"$acc"
    have=$(wc -l <"$acc"); page=$((page + 1))
    [ "$(jq length "$pg")" -ge 100 ] || break
  done
  rm -f "$pg"
  local shaped
  shaped=$(jq -sc --argjson n "$limit" ".[:\$n] | map($_REST_ISSUE_JQ + {comments: []})" "$acc"); rm -f "$acc"
  if [ -n "$fields" ]; then
    jq -c --arg f "$fields" '($f | split(",")) as $k | map(. as $i | reduce $k[] as $x ({}; .[$x] = $i[$x]))' <<<"$shaped" | _rest_emit_json
  else
    jq -r '.[] | "\(.number)\t\(.state)\t\(.title)\t\([.labels[].name] | join(", "))\t\(.updatedAt)"' <<<"$shaped"
  fi
}

# ---- writes -----------------------------------------------------------------
_rest_comment() {
  local num="" body="" have=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -b|--body|--body=*) _take "$@"; body=$VAL; have=1; shift "$SHIFT" ;;
      -F|--body-file|--body-file=*) _take "$@"; body=$(_rest_body "$VAL"; echo x); body=${body%x}; have=1; shift "$SHIFT" ;;
      -R|--repo|--repo=*) _take "$@"; REST_REPO=$VAL; shift "$SHIFT" ;;
      -*) _rest_die "issue comment: unsupported flag $1" ;;
      *) num=$(_rest_num "$1") || exit $?; shift ;;
    esac
  done
  [ -n "$num" ] && [ "$have" = 1 ] || _rest_die "issue comment needs <number> and --body/--body-file"
  _rest_repo
  jq -n --arg b "$body" '{body: $b}' | _rest_api -X POST "repos/$REST_REPO/issues/$num/comments" --input - --jq .html_url
}

_rest_state() { # _rest_state close|reopen <args>
  local verb=$1; shift
  local num="" reason="" comment=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -r|--reason|--reason=*) _take "$@"; reason=$VAL; shift "$SHIFT" ;;
      -c|--comment|--comment=*) _take "$@"; comment=$VAL; shift "$SHIFT" ;;
      -R|--repo|--repo=*) _take "$@"; REST_REPO=$VAL; shift "$SHIFT" ;;
      -*) _rest_die "issue $verb: unsupported flag $1" ;;
      *) num=$(_rest_num "$1") || exit $?; shift ;;
    esac
  done
  [ -n "$num" ] || _rest_die "issue $verb needs an issue number"
  _rest_repo
  local patch
  if [ "$verb" = close ]; then
    case "$reason" in
      ""|completed) reason=completed ;;
      "not planned"|not_planned) reason=not_planned ;;
      duplicate) ;;
      *) _rest_die "issue close: bad --reason '$reason'" ;;
    esac
    patch=$(jq -n --arg r "$reason" '{state: "closed", state_reason: $r}')
  else
    patch='{"state":"open","state_reason":"reopened"}'
  fi
  if [ -n "$comment" ]; then
    jq -n --arg b "$comment" '{body: $b}' | _rest_api -X POST "repos/$REST_REPO/issues/$num/comments" --input - --silent || exit $?
  fi
  _rest_api -X PATCH "repos/$REST_REPO/issues/$num" --input - --silent <<<"$patch" || exit $?
  echo "✓ ${verb^}d issue #$num" >&2
}

# _rest_milestone <title|number> -> milestone number
_rest_milestone() {
  [[ "$1" =~ ^[0-9]+$ ]] && { echo "$1"; return; }
  local n
  n=$(_rest_api --paginate "repos/$REST_REPO/milestones?state=all&per_page=100" --jq ".[] | select(.title == \"${1//\"/\\\"}\") | .number" | head -1) || exit $?
  [ -n "$n" ] || _rest_die "no milestone titled '$1'"
  echo "$n"
}

_rest_edit() {
  local num="" title="" body="" milestone="" rm_ms=0 add="" rem="" add_as="" rem_as=""
  local set_title=0 set_body=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -t|--title|--title=*) _take "$@"; title=$VAL; set_title=1; shift "$SHIFT" ;;
      -b|--body|--body=*) _take "$@"; body=$VAL; set_body=1; shift "$SHIFT" ;;
      -F|--body-file|--body-file=*) _take "$@"; body=$(_rest_body "$VAL"; echo x); body=${body%x}; set_body=1; shift "$SHIFT" ;;
      --add-label|--add-label=*) _take "$@"; add=${add:+$add,}$VAL; shift "$SHIFT" ;;
      --remove-label|--remove-label=*) _take "$@"; rem=${rem:+$rem,}$VAL; shift "$SHIFT" ;;
      --add-assignee|--add-assignee=*) _take "$@"; add_as=${add_as:+$add_as,}$VAL; shift "$SHIFT" ;;
      --remove-assignee|--remove-assignee=*) _take "$@"; rem_as=${rem_as:+$rem_as,}$VAL; shift "$SHIFT" ;;
      -m|--milestone|--milestone=*) _take "$@"; milestone=$VAL; shift "$SHIFT" ;;
      --remove-milestone) rm_ms=1; shift ;;
      -R|--repo|--repo=*) _take "$@"; REST_REPO=$VAL; shift "$SHIFT" ;;
      --parent|--parent=*|--add-blocked-by*|--remove-blocked-by*|--add-blocking*|--remove-blocking*|--remove-parent|--add-project*|--remove-project*|--add-sub-issue*|--remove-sub-issue*)
        _rest_gql_only "issue edit ${1%%=*}" ;;
      -*) _rest_die "issue edit: unsupported flag $1" ;;
      *) [ -z "$num" ] || _rest_die "issue edit: one issue at a time"; num=$(_rest_num "$1") || exit $?; shift ;;
    esac
  done
  [ -n "$num" ] || _rest_die "issue edit needs an issue number"
  _rest_repo
  local patch="{}"
  [ "$set_title" = 0 ] || patch=$(jq -c --arg v "$title" '. + {title: $v}' <<<"$patch")
  [ "$set_body" = 0 ] || patch=$(jq -c --arg v "$body" '. + {body: $v}' <<<"$patch")
  if [ -n "$milestone" ]; then
    local ms; ms=$(_rest_milestone "$milestone") || exit $?
    patch=$(jq -c --argjson v "$ms" '. + {milestone: $v}' <<<"$patch")
  fi
  [ "$rm_ms" = 0 ] || patch=$(jq -c '. + {milestone: null}' <<<"$patch")
  if [ "$patch" != "{}" ]; then
    _rest_api -X PATCH "repos/$REST_REPO/issues/$num" --input - --silent <<<"$patch" || exit $?
  fi
  local l
  if [ -n "$add" ]; then
    jq -nc --arg v "$add" '{labels: ($v | split(","))}' | _rest_api -X POST "repos/$REST_REPO/issues/$num/labels" --input - --silent || exit $?
  fi
  if [ -n "$rem" ]; then
    IFS=, read -ra ls <<<"$rem"
    for l in "${ls[@]}"; do
      # An already-absent label is a no-op, as in gh.
      _rest_api -X DELETE "repos/$REST_REPO/issues/$num/labels/$(jq -rn --arg v "$l" '$v|@uri')" --silent 2>/dev/null || true
    done
  fi
  if [ -n "$add_as" ]; then
    jq -nc --arg v "$add_as" '{assignees: ($v | split(","))}' | _rest_api -X POST "repos/$REST_REPO/issues/$num/assignees" --input - --silent || exit $?
  fi
  if [ -n "$rem_as" ]; then
    jq -nc --arg v "$rem_as" '{assignees: ($v | split(","))}' | _rest_api -X DELETE "repos/$REST_REPO/issues/$num/assignees" --input - --silent || exit $?
  fi
  echo "https://github.com/$REST_REPO/issues/$num"
}

_rest_create() {
  local title="" body="" milestone="" labels="" assignees=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -t|--title|--title=*) _take "$@"; title=$VAL; shift "$SHIFT" ;;
      -b|--body|--body=*) _take "$@"; body=$VAL; shift "$SHIFT" ;;
      -F|--body-file|--body-file=*) _take "$@"; body=$(_rest_body "$VAL"; echo x); body=${body%x}; shift "$SHIFT" ;;
      -l|--label|--label=*) _take "$@"; labels=${labels:+$labels,}$VAL; shift "$SHIFT" ;;
      -a|--assignee|--assignee=*) _take "$@"; assignees=${assignees:+$assignees,}$VAL; shift "$SHIFT" ;;
      -m|--milestone|--milestone=*) _take "$@"; milestone=$VAL; shift "$SHIFT" ;;
      -R|--repo|--repo=*) _take "$@"; REST_REPO=$VAL; shift "$SHIFT" ;;
      --parent|--parent=*|-p|--project|--project=*|--blocked-by*|--blocking*) _rest_gql_only "issue create ${1%%=*}" ;;
      -*) _rest_die "issue create: unsupported flag $1" ;;
      *) _rest_die "issue create: unexpected argument $1" ;;
    esac
  done
  [ -n "$title" ] || _rest_die "issue create needs --title (no interactive prompts)"
  _rest_repo
  local ms=null
  if [ -n "$milestone" ]; then ms=$(_rest_milestone "$milestone") || exit $?; fi
  jq -nc --arg t "$title" --arg b "$body" --arg l "$labels" --arg a "$assignees" --argjson m "$ms" \
    '{title: $t, body: $b} + (if $l != "" then {labels: ($l | split(","))} else {} end)
     + (if $a != "" then {assignees: ($a | split(","))} else {} end) + (if $m != null then {milestone: $m} else {} end)' \
    | _rest_api -X POST "repos/$REST_REPO/issues" --input - --jq .html_url
}

# gh_rest_dispatch <gh args...> — exits; never returns.
gh_rest_dispatch() {
  local cmd=${1:-} sub=${2:-}
  case "$cmd" in
    issue)
      shift 2 2>/dev/null || shift $#
      case "$sub" in
        view) _rest_view "$@" ;;
        list) _rest_list "$@" ;;
        comment) _rest_comment "$@" ;;
        close) _rest_state close "$@" ;;
        reopen) _rest_state reopen "$@" ;;
        edit) _rest_edit "$@" ;;
        create) _rest_create "$@" ;;
        *) _rest_gql_only "issue ${sub:-<none>}" ;;
      esac
      exit $? ;;
    project|pr|discussion) _rest_gql_only "gh $cmd" ;;
  esac
  return 1
}
