#!/bin/zsh
#no args to read book from menu, file args to update location of existing books or add single book
#deps: rofi, zathura configured to use sqlite, suckless tabbed

datadir=/home/d/sync/configs

xidfile=/tmp/tabbed-surf.xid
zfile=$datadir/bookmarks.sqlite

runtabbed() {
	echo opening $@
	tabbed -dn tabbed-surf -r 2 zathura -e '' $@ -d "$datadir" > "$xidfile"
	#tabbed -g 2000x2000 -dn tabbed-surf -r 2 zathura -e '' "$1" -d "$datadir" > "$xidfile"
}

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

connectkindle(){
	[ -d $pdrdir ] && [ ! -z $pdrdir ] && echo connected to $pdrdir && return 0
	pluggedin=$(lsblk -l -o NAME,LABEL,MOUNTPOINTS | grep Kindle | head -n 1)
	case $(echo $pluggedin | wc -w) in
		2) dev=$(echo $pluggedin | awk '{print $1; exit}')
			udisksctl mount -b /dev/$dev
			pdrdir=$(lsblk -l -o LABEL,MOUNTPOINTS | grep Kindle | awk '{print $2; exit}') ;;
		3) pdrdir=$(echo $pluggedin | awk '{print $3; exit}');;
	esac
	pdrdir=${pdrdir}/documents/rbooks
	[ -d $pdrdir ] || { echo not connect to kindle; return 1 }
	echo connected to $pdrdir
	return 0
}

getpdrfile(){
	pdrfile=$pdrdir/${1//pdf/pdr}
	[ ! -w $pdrfile ] && return 1
	echo $pdrfile
}

getkindlepage(){
	file=$(getpdrfile $1) || {
		pdffile=$pdrdir/$1
		if [ -r $pdffile ]; then
			echo "deadcabb010000000000000000" | xxd -p -r > $pdrdir/${1//pdf/pdr}
			echo 0; return 0
		else
			return 1
		fi
	}
	page=$(printf "%d" 0x$(xxd -s +7 -l 2 -p $file))
	echo $page
}

setkindlepage(){
	file=$(getpdrfile $1) || return 1
	printf "%04x" $2 | xxd -p -r | dd of=$file seek=7 conv=notrunc obs=1 count=2 status=none
	echo "$1 set to $2"
}

synckindle(){
	[[ $1 =~ .*epub$ ]] && return
	echo syncing $1
	connectkindle || return
	basename=$(basename $1)
	kindlepage=$(getkindlepage $basename) || { echo $basename not on kindle; return }
	zathurapage=$(sqlite3 $zfile "select max(coalesce(max(bookmarks.page),0), coalesce(max(fileinfo.page),0)) from fileinfo left join bookmarks using(file) where file ='$1'")
	[ -z $zathurapage ] && echo "$basename not in zathura db" && return
	echo "book: $basename zathura: $zathurapage kindle: $kindlepage"
	#kindlepage is one less than what it opens to
	let kindlepage++
	if [ $zathurapage -gt $kindlepage ]; then
		setkindlepage $basename $zathurapage
	elif [ $zathurapage -lt $kindlepage ]; then
		bookmark=$kindlepage
	fi
}

syncallkindle(){
	echo updating all kindle bookmarks
	books=$(sqlite3 $zfile 'select file from fileinfo')
	for bookpath (${(f)books}); do
		synckindle $bookpath
	done
	exit
}

opentolastpage(){
	[ ! -r $1 ] && echo $1 not found && return
	bookmark=$(sqlite3 $zfile "select max(case when bookmarks.page > fileinfo.page then bookmarks.page end) from fileinfo left join bookmarks using(file) where file ='$1'")
	synckindle $1
	if [ -z $bookmark ]; then
		zathuratab $1
	else
		zathuratab -P $bookmark $1
	fi
}

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
	roficmd="rofi -lines 25 -width 70 -dmenu -matching fuzzy -i -markup-rows $dpi"
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

dropbook(){
	book=$(pickbook)
	[ -z $book ] && return	
	sqlite3 $zfile "delete from fileinfo where file = '$book'"
	echo deleted $book from database
	exit
}

readbook(){
	book=$(pickbook)
	[ -z $book ] && return	
	opentolastpage $book
}

[ $# -eq 0 ] && readbook
[ $# -gt 0 ] && {
	[ $1 = k ] && syncallkindle
	[ $1 = d ] && dropbook
	[ $# -gt 1 ] && noread=true
	for book in "$@"; do
		handlearg "$book"
	done
}
