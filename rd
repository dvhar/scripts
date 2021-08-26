#!/bin/zsh
#no args to read book from menu, file args to update location of existing books or add single book
#deps: rofi, zathura configured to use sqlite, suckless tabbed

datadir=/home/d/sync/configs

xidfile=/tmp/tabbed-surf.xid
zfile=$datadir/bookmarks.sqlite

runtabbed() {
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
			zathura -e $xid $@ -d $datadir --fork
		fi
	fi
}

getpdrfile(){
	[ -z $pdrpath ] && {
		knum=$(echo $pluggedin | wc -w)
		case $knum in
			2) dev=$(echo $pluggedin | awk '{print $1; exit}')
				udisksctl mount -b /dev/$dev
				pdrpath=$(lsblk -l -o NAME,LABEL,MOUNTPOINTS | grep Kindle | awk '{print $3; exit}') ;;
			3) pdrpath=$(echo $pluggedin | awk '{print $3; exit}');;
		esac
	}
	[ -z $pdrpath ] && return 1
	pdrdir=${pdrpath}/documents/rbooks
	pdrfile=$pdrdir/${1//pdf/pdr}
	[ ! -w $pdrfile ] && return 1
	echo $pdrfile
}

getkindlepage(){
	file=$(getpdrfile $1) || return 1
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
	pluggedin=$(lsblk -l -o NAME,LABEL,MOUNTPOINTS | grep Kindle | head -n 1)
	[ -z $pluggedin ] && return
	basename=$(basename $1)
	zathurapage=$(sqlite3 $zfile "select max(coalesce(max(bookmarks.page),0), coalesce(max(fileinfo.page),0)) from fileinfo left join bookmarks using(file) where file ='$1'")
	[ -z $zathurapage ] && return
	kindlepage=$(getkindlepage $basename)
	[ -z $kindlepage ] && return
	#kindlepage is one less than what it opens to
	let kindlepage++
	if [ $zathurapage -gt $kindlepage ]; then
		setkindlepage $basename $((zathurapage-1))
	elif [ $zathurapage -lt $kindlepage ]; then
		bookmark=$kindlepage
	fi
}

opentolastpage(){
	bookmark=$(sqlite3 $zfile "select max(case when bookmarks.page > fileinfo.page then bookmarks.page end) from fileinfo left join bookmarks using(file) where file ='$1'")
	synckindle $1
	if [ -z $bookmark ]; then
		zathuratab $1
	else
		zathuratab -P $bookmark $1
	fi
}

handlearg(){
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
	books=$(sqlite3 $zfile 'select file from fileinfo;')
	book=$(
	for bookpath (${(f)books}); do
		basename $bookpath
	done | eval $roficmd)
	for bookpath (${(f)books}); do
		if [ "$(basename $bookpath)" = "$book" ]; then
			[[ -f "$bookpath" ]] && openbook=$bookpath
			break
		fi
	done
	[ -z $openbook ] || opentolastpage $openbook
}

[ $# -eq 0 ] && pickbook
[ $# -gt 0 ] && {
	[ $# -gt 1 ] && noread=true
	for book in "$@"; do
		handlearg "$book"
	done
}
