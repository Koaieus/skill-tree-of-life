# Sourced by the test:one / test:dir wrappers (mise.toml).
# res_path <kind: file|dir> <arg> -> prints the res:// form, or exits 2 with a
# message when the path is not in the project. Accepts `res://x`, `x`, `./x`
# and an absolute path under the project root.
res_path() {
  local kind="$1" p="$2" root="${MISE_PROJECT_ROOT:-$PWD}" rel
  case "$p" in
    res://*) rel="${p#res://}" ;;
    "$root"/*) rel="${p#"$root"/}" ;;
    *) rel="${p#./}" ;;
  esac
  if [ "$kind" = file ] && [ ! -f "$root/$rel" ]; then
    echo "✗ no such test script: $p (looked for $root/$rel)" >&2; return 2
  fi
  if [ "$kind" = dir ] && [ ! -d "$root/$rel" ]; then
    echo "✗ no such test directory: $p (looked for $root/$rel)" >&2; return 2
  fi
  echo "res://$rel"
}
