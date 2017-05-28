#!/bin/bash


TTYFILE=/dev/ttyACM0

usage() {
	$0 file
	Will output from uart device to specified file with timestamp values

if [ "$(set -x; sudo stty -F $TTYFILE speed;)" -ne "115200" ]; then
        (
                set -x
                sudo stty -F $TTYFILE 115200
        )
fi
( 
        set -x;
        timeout 0.1 cat $TTYFILE >/dev/null || true
)

cat $TTYFILE | while IFS= read -r line; do echo "$(date "+%s.%n") $line"; done > $file


