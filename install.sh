#!/bin/bash -x

for a in *.sh; do
	f="${a%.*}"
	[[ $a == install.sh ]] || sudo ln -sf $(realpath "$a") /usr/local/bin/"$f"
done
