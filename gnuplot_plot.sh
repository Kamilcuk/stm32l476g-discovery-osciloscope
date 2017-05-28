#!/bin/bash -e

DEBUG=${DEBUG:-false}
$DEBUG && set -x

TTYFILE=/dev/ttyACM0

#FILTER = NUMLINES or SINCE
FILTER=${FILTER:-NUMLINES}
FILTERNUMLINES=${FILTERNUMLINES:-100}
FILTERSINCE=${FILTERSINCE:-60} # in seconds

#######################################################################3


################### genData definitions ####################################

case "${FILTER,,}" in
"numlines")
	echo "Filtering using numlines - FILTERNUMLINES=${FILTERNUMLINES}"
	genDataFilter() {
		tail -n $(( FILTERNUMLINES - 1)) $1
	}
	;;
"since")
	echo "Filtering using since - FILTERSINCE=${FILTERSINCE}"
	genDataFilter() {
		if [ ! -s "$1" ]; then
			return
		fi
		read -r sec nano < <(date "--date=${FILTERSINCE} seconds ago" '+%s %N')
	{
		while read -r outline ; do
			#echo "outline=\"$outline\"" >&2
			read -r sec2 nano2 < <(echo "${outline}"|cut -d',' -f1|tr '.' ' ')
			if [ "$sec2" -eq "$sec" ]; then
				if [ "$nano2" -ge "$nano" ]; then
					break;
				fi
			elif [ "$sec2" -gt "$sec" ]; then
				break;
			fi
		done 
		if [ -n "$outline" ]; then
			echo "$outline"
		fi
		cat
	} <"$1"
	}
	;;
*)
	echo "No filtering"
	genDataFilter() {
		cat $1
	}
	;;
esac
genData() {
	local infile outfile inline outline
	local sec nano sec2 nano2
	local times
	infile=$1
	outfile=$2
	times=5
	{
		timeout 0.1 cat >/dev/null || true
		while IFS= read -r inline; do 
			#echo ">>> New inline: $(date '+%T.%N') \"$inline\"" >&2
			if echo "$inline" | grep -q "IddReadValue="; then
				{
					genDataFilter "$outfile"
					IddReadValue=$(echo "$inline"|sed 's/.*IddReadValue=[ ]*\([0-9]*\).*/\1/')
					if [ "$IddReadValue" -eq "$IddReadValue" ] >/dev/null ; then
						IddReadValue=$(echo "$IddReadValue/100000"|bc)
						echo "$(date '+%s.%N'),$IddReadValue"
					else
						echo "IddReadValue=\"$IddReadValue\" is not a number!" >&2
					fi

				} | sponge $outfile
				
				if [ $((times%10)) -eq 0 ]; then
					echo ">>> Outfile lines: $(cat $outfile | wc -l). Last line:\"$(cat $outfile | tail -n1)\" Inline: ${inline}" >&2
				fi
				times=$((times+1))

				#echo "outfile: ---"
				#cat $outfile
				#echo "------------"
			fi
		done 
	} <$infile
	exit
}

runGnuPlot() {
	local tempfile plotdata
	tempfile=$2
	plotdata=$1

 	# wait for 2 lines in plotdata
	while sleep 1; do 
		if [ $(cat $plotdata | wc -l) -gt 2 ]; then 
			break; 
		fi; 
	done;

	# create gnuplot config file
	cat >$tempfile <<EOF
set title "Pomiar pradu z stm32l765g-discovery"
set xlabel "Czas [min:sec]"
set ylabel "Prad [miliampery]"
set t wxt noraise
set key off
set grid

set xdata time
set timefmt "%s"
set datafile separator ","
set format x "%M:%S"
set format y "%f"

plot "$plotdata" using 1:2 with lines
while(1) {
	pause 1
	replot
}
EOF
	gnuplot -noraise $gnuplotgnu
}

############################# main #################################

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

plotdata=$(mktemp)
gnuplotgnu=$(mktemp)
fifo=$(mktemp); rm $fifo; mkfifo $fifo
tmp1=$(mktemp)
tmp2=$(mktemp)
cleartemp() { rm -f $plotdat $gnuplotgnu $fifo $tmp1 $tmp2; }

childs=""
trap '[ -n "$childs" ] && { kill $childs; }; wait; cleartemp;' EXIT
trap '[ -n "$childs" ] && { kill $childs; }; exit 1;' SIGINT

echo "Runnning fifocat $TTYFILE > fifo:$fifo"
( 
	trap 'echo "fifocat end";' EXIT; 
	cat $TTYFILE >$fifo; 
) &
childs+=" $!"

echo "Runnning genData fifo:$fifo > plotdata:$plotdata"
(
	trap 'echo "genData end";' EXIT;
	genData $fifo $plotdata;
) &
childs+=" $!"

echo "Runnning gnuplot"
runGnuPlot $plotdata $gnuplotgnu

set -x;
kill $childs;
wait;

