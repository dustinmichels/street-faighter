#!/usr/bin/env bash
# Launch two connected instances side by side (host + join on 127.0.0.1:7777).
set -u
# --no-upnp: a local match needs no port forwarded on the router.
godot --path . --resolution 960x540 --position 0,40 -- --host --no-upnp --name=HOST &
host=$!
sleep 1
godot --path . --resolution 960x540 --position 960,40 -- --join=127.0.0.1:7777 --name=GUEST &
guest=$!
trap 'kill $host $guest 2>/dev/null' EXIT INT TERM
wait
