#!/bin/bash -x

for a in ./*.sh; do
	f="${a%.*}"
#	[[ $(basename $a) == inst.sh ]] || sudo ln -sf $(realpath "$a") /usr/local/bin/"$f"
        [[ $(basename $a) == inst.sh ]] || sudo cp --remove-destination $(realpath "$a") /usr/local/bin/"$f"
	[[ -f /usr/local/bin/"$f" ]] && sudo chmod a+x /usr/local/bin/"$f"

done

[ $(command -v inotifywait) ] || sudo apt -y install inotify-tools
[ $(command -v mc) ] || sudo apt -y install mc
