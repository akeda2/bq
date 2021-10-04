#!/bin/bash -x

for a in *.sh; do
	f="${a%.*}"
	[[ $a == install.sh ]] || sudo ln -sf $(realpath "$a") /usr/local/bin/"$f"
done

[ $(command -v inotifywait) ] || sudo apt -y install inotify-tools
[ $(command -v mc) ] || sudo apt -y install mc