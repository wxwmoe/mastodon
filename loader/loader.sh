# The directory lock stays open in build.sh until both Docker builds finish.
APPLY() {
  if [[ ! /dev/fd/${wxw_build_lock:-closed} -ef . ]]; then
    exec {wxw_build_lock}<. || return 1
  fi
  flock -n "$wxw_build_lock" || { echo "E: Another build is using this directory." >&2; return 1; }
  python3 loader/apply.py "$MASTODON_VERSION" "${build_mode:-}"
}
