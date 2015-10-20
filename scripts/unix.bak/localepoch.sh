#!/bin/sh

# Convert a epoch time into 'local epoch' -- i.e. convert UTC epoch seconds into local epoch seconds

get_tz_offset(){
	szLocalOffset=$(date '+%z')

	if [ $(echo "$szLocalOffset" | egrep '\+' | wc -l) -gt 0 ]; then
		IsWest=0
	else
		IsWest=1
	fi

	szLocalOffsetHours="${szLocalOffset:1:2}"
	szLocalOffsetHours=$((10#$szLocalOffsetHours*3600))
	szLocalOffsetMinutes="${szLocalOffsetStr:3:2}"
	szLocalOffsetMinutes=$((10#$szLocalOffsetMinutes*60))
	szLocalOffsetSeconds=$((10#$szLocalOffsetHours+10#$szLocalOffsetMinutes))

	if [ $IsWest -gt 0 ]; then
		szLocalOffsetSeconds=-$szLocalOffsetSeconds
	fi

	echo "$szLocalOffsetSeconds"
}


UTCEPOCH="$1"

if [ -z "$UTCEPOCH" ]; then
	UTCEPOCH=$(date --utc '+%s')
fi

TZOFFSET=$(get_tz_offset)

LOCALEPOCH=$(($UTCEPOCH+$TZOFFSET))

echo $UTCEPOCH
echo $LOCALEPOCH