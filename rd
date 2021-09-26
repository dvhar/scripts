#!/bin/zsh
#deps: rofi, fzf, zathura configured to use sqlite, suckless tabbed, calibre, jq

datadir=/home/d/sync/configs

xidfile=/tmp/tabbed-rd.xid
zfile=$datadir/bookmarks.sqlite

runtabbed() {
	echo opening $@
	tabbed -dn tabbed-rd -r 2 zathura -e '' $@ -d "$datadir" > "$xidfile"
	#tabbed -g 2000x2000 -dn tabbed-rd -r 2 zathura -e '' "$1" -d "$datadir" > "$xidfile"
}

#args: book or -P page book
zathuratab(){
	if [ ! -r $xidfile ]; then
		runtabbed $@
	else
		xid=$(cat $xidfile)
		xprop -id $xid >/dev/null 2>&1
		if [ $? -gt 0 ];
		then
			runtabbed $@
		else
			echo opening $@
			zathura -e $xid $@ -d $datadir --fork
		fi
	fi
}

#no args
connectkindle(){
	[ -d $pdrdir ] && [ ! -z $pdrdir ] && return 0
	pluggedin=$(lsblk -l -o NAME,LABEL,MOUNTPOINTS | grep Kindle | head -n 1)
	case $(echo $pluggedin | wc -w) in
		2) dev=$(echo $pluggedin | awk '{print $1; exit}')
			udisksctl mount -b /dev/$dev
			pdrdir=$(lsblk -l -o LABEL,MOUNTPOINTS | awk '/Kindle/{print $2; exit}') ;;
		3) pdrdir=$(echo $pluggedin | awk '{print $3; exit}');;
	esac
	pdrdir=${pdrdir}/documents/rbooks
	[ -d $pdrdir ] || { echo not connected to kindle; unset pdrdir; return 1 }
	echo connected to $pdrdir
	return 0
}

#args: pdf filepath
getpdrfile(){
	pdrfile=$pdrdir/${1//pdf/pdr}
	[ ! -w $pdrfile ] && return 1
	echo $pdrfile
}

#args: pdf filepath
getkindlepage(){
	file=$(getpdrfile $1) || {
		pdffile=$pdrdir/$1
		if [ -r $pdffile ]; then
			echo "deadcabb010000000000000000" | xxd -p -r > $pdrdir/${1//pdf/pdr}
			echo 0; return 0
		else
			echo "could no read $pdffile" > /dev/stderr
			return 1
		fi
	}
	kindlepage=$(printf "%d" 0x$(xxd -s +7 -l 2 -p $file))
	#let kindlepage++ #kindlepage is one less than what it opens to
	echo $kindlepage
}

#pargs pdf filepath, page number
setkindlepage(){
	file=$(getpdrfile $1) || return 1
	printf "%04x" $2 | xxd -p -r | dd of=$file seek=7 conv=notrunc obs=1 count=2 status=none
	echo "set $1 to $2"
}

connectandroid(){
	lsusb | grep Android
	[ $? -ne 0 ] && return 1;
	phonereadfile='mtp:/G8 ThinQ/Internal shared storage/Librera/profile.Librera/device.LM-G820/app-Progress.json'
	phonewritefile='/home/d/mnt/phone/Internal shared storage/Librera/profile.Librera/device.LM-G820/app-Progress.json'
}

#args: pdf filepath
getphonepage(){
	connectandroid || return 1
	[ -z $progjson ] && progjson=$(kioclient5 cat $phonereadfile)
	totalpages=$(pdfinfo $1 | awk '/Pages/{print $2}')
	percent=$(echo $progjson | jq ".\"$(basename $1)\".p")
	[ -z $percent ] && return 1
	printf '%.0f' $((percent * totalpages))
}

setphonepages(){
	[ -z $phoneupdates ] && return 1
	phoneupdates='{'$phoneupdates[2,-1]'}'
	connectandroid || return 1
	[ -z $progjson ] && return 1
	pkill kiod5 || { echo 'failed to stop kiod5'; return 1 }
	aft-mtp-mount ~/mnt/phone || { echo 'failed to mount phone with aft'; return 1 }
	updater="import json,sys; true=True; false=False
newvals = $phoneupdates
fullvals = $progjson
changed = False
for book in newvals:
	if book in fullvals:
		fullvals[book]['p'] = max(newvals[book],fullvals[book]['p'])
		changed = True
		sys.stderr.write('updating phone ' + book)
if changed:
	json.dump(fullvals, sys.stdout, separators=(',', ':'))"
	python -c $updater > $phonewritefile
}

#args: page, pdf filepath
pagetoportion(){
	totalpages=$(pdfinfo $2 | awk '/Pages/{print $2}')
	progress=$(($1 / $totalpages.0))
	echo $progress[1,12]
}

#args: pdf filepath
syncdevices(){
	echo attempting to sync $1
	connectkindle || connectandroid || return 1
	basename=$(basename $1)
	echo syncing $basename
	local zathurapage=$(sqlite3 $zfile "select max(coalesce(max(bookmarks.page),0), coalesce(max(fileinfo.page),0)) from fileinfo left join bookmarks using(file) where file ='$1'")
	[ -z $zathurapage ] && echo "$basename not in zathura db" && return 1
	[[ $1 =~ pdf$ ]] && {
		echo "$basename is pdf"
		local kindlepage=$(getkindlepage $basename) || echo $basename not on kindle
		local phonepage=$(getphonepage $1) || echo $basename not on phone
		echo "found: $basename zathura: '$zathurapage' kindle: '$kindlepage' phone: '$phonepage'"
	}
	[ -z $kindlepage ] && [ -z $phonepage ] && { echo $basename page not found on devices; return 1 }
	local maxpage=0
	[ ! -z $kindlepage ] && maxpage=$((kindlepage > zathurapage ? kindlepage : zathurapage))
	[ ! -z $phonepage ] && maxpage=$((maxpage > phonepage ? maxpage : phonepage))
	((zathurapage > maxpage)) && maxpage=$zathurapage
	((maxpage > zathurapage)) && bookmark=$maxpage
	[ ! -z $kindlepage ] && ((maxpage > kindlepage)) && setkindlepage $basename $maxpage
	[ ! -z $phonepage ] && ((maxpage > phonepage)) && phoneupdates+=",\"$basename\":$(pagetoportion $maxpage $1)"
}

syncalldevice(){
	echo updating all device bookmarks
	books=$(sqlite3 $zfile 'select file from fileinfo')
	for bookpath (${(f)books}); do
		syncdevices $bookpath
	done
	setphonepages
	exit
}

#args: book filepath
opentolastpage(){
	[ ! -r $1 ] && echo $1 not found && return
	bookmark=$(sqlite3 $zfile "select max(case when bookmarks.page > fileinfo.page then bookmarks.page end) from fileinfo left join bookmarks using(file) where file ='$1'")
	syncdevices $1
	setphonepages
	if [ -z $bookmark ]; then
		zathuratab $1
	else
		zathuratab -P $bookmark $1
	fi
}

#args: book filename
handlearg(){
	[ ! -r $1 ] && echo $1 not found && return
	fullpath=$(realpath $1)
	basename=$(basename $1)
	updateq="update fileinfo set file = '$fullpath' where file like '%$basename%'"
	findq="select file from fileinfo where file like '%$basename%'"
	found=$(sqlite3 $zfile $findq)
	[ ! -z $found ] && [ ! -e $found ] && sqlite3 $zfile "$updateq"
	[ -z $noread ] && opentolastpage $fullpath
}

pickbook(){
	vres=$(xrandr | grep primary | egrep -o '[0-9]+x[0-9]+' | cut -d'x' -f2)
	[ $vres -gt 2000 ] && dpi='-dpi 200'
	roficmd="rofi -l 25 -theme-str 'window {width: 70%;}' -dmenu -matching fuzzy -i -markup-rows $dpi"
	[ -z $DISPLAY ] && roficmd=fzf
	books=$(sqlite3 $zfile 'select file from fileinfo')
	book=$(
	for bookpath (${(f)books}); do
		basename $bookpath
	done | eval $roficmd)
	for bookpath (${(f)books}); do
		if [ "$(basename $bookpath)" = "$book" ]; then
			[ -r $bookpath ] && echo $bookpath
			break
		fi
	done
}

synconedevice(){
	book=$(pickbook)
	[ -z $book ] && exit	
	[[ $book =~ pdf$ ]] || exit
	connectkindle || connectandroid || exit
	[ ! -z $pdrdir ] && {
		target=${pdrdir}/$(basename $book)
		[ -r $target ] || cp -v $book $pdrdir
	}
	syncdevices $book
	setphonepages
	notify-send "synced book to devices"
	exit
}

dropbook(){
	book=$(pickbook)
	[ -z $book ] && exit	
	sqlite3 $zfile "delete from fileinfo where file = '$book'"
	echo deleted $book from database
	exit
}

readbook(){
	book=$(pickbook)
	[ -z $book ] && exit	
	opentolastpage $book
}

convertpdf(){
	book=$(pickbook)
	[[ ! $book =~ epub$ ]] && exit
	[ ! -r $book ] && exit	
	newbook=${book//.epub/.pdf}
	echo "creating new book $newbook"
	ebook-convert $book $newbook
	opentolastpage $newbook
}

usage(){
	cat << EOF
usage:
    No args to read book from menu.
    Args:
      h: Show this help menu.
      s: Sync one book with device from menu and add it if not on device.
      k: Sync all books with device if present.
      d: Delete book from database file (not delete book file).
      c: Convert selected epub to pdf.
      Any number of pdf/epub files:
        Add a book and open it, update locations of moved books
EOF
	exit
}

[ $# -eq 0 ] && readbook
[ $# -gt 0 ] && case $1 in
	h ) usage;;
	k ) syncalldevice;;
	s ) synconedevice;;
	d ) dropbook;;
	c ) convertpdf;;
	* ) [ $# -gt 1 ] && noread=true
		for book in "$@"; do
			handlearg "$book"
		done;;
	esac
