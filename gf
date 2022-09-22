#!/bin/bash

fetch(){
	git fetch origin "$1:$1"
	git checkout "$1"
}

if [ $# -gt 0 ]; then
	fetch "$1"
else
	git fetch
	rem=`git branch -r | grep -v HEAD | sed 's/ //g;s-origin/--g'`	
	new=$(echo "$rem" | fzf --height $(($(echo "$rem" | wc -l)+2)))
	[ -z "$new" ] && exit
	echo $new
	fetch "$new"
fi
