#!@shell@
set -eu

# The server resolves `static/` and the default `./server/config.json` against
# its working directory, and the Nix store is read-only.  Run it from a
# writable per-user state directory that links the packaged web UI and holds
# config.json/data.json.  MOONLIGHT_WEB_HOME overrides the location for
# service managers without HOME.
state_dir=${MOONLIGHT_WEB_HOME:-${XDG_STATE_HOME:-${HOME:?HOME is not set; set MOONLIGHT_WEB_HOME}/.local/state}/moonlight-web}
mkdir -p "$state_dir/server"
ln -sfn "@out@/lib/moonlight-web/static" "$state_dir/static"
cd "$state_dir"
exec "@out@/lib/moonlight-web/web-server" "$@"
