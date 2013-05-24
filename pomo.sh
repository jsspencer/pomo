#!/bin/bash

# Copyright (c) 2013, James Spencer.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

[[ -n $POMO_FILE ]] && POMO=$POMO_FILE || POMO=$HOME/.local/share/pomo

[[ -n $POMO_WORK_TIME ]] && WORK_TIME=$POMO_WORK_TIME || WORK_TIME=1
[[ -n $POMO_BREAK_TIME ]] && BREAK_TIME=$POMO_BREAK_TIME || BREAK_TIME=1

test -e $(dirname $POMO) || mkdir $(dirname $POMO) 

function pomo_start {
    # Start new pomo block (work+break cycle).
    touch $POMO
}

function pomo_stop {
    # Stop pomo cycles.
    rm $POMO
}

function pomo_pause {
    # Pause a pomo block.
    pomo_stat > $POMO
}

function pomo_ispaused {
    # Return 0 if paused, 1 otherwise.
    [[ $(wc -l $POMO | cut -d" " -f1) -gt 0 ]]
    return $?
}

function pomo_restart {
    # Restart a paused pomo block by updating the time stamp of the POMO file.
    running=$(cat $POMO)
    mtime=$(date --date "$(date) - $running seconds" +%m%d%H%M.%S)
    echo > $POMO # erase saved time stamp.
    touch -m -t $mtime $POMO
}

function pomo_update {
    # Update the time stamp on POMO a new cycle has started.
    running=$(pomo_stat)
    block_time=$(( (WORK_TIME+BREAK_TIME)*60 ))
    if [[ $running -gt $block_time ]]; then
        ago=$((running - block_time))
        mtime=$(date --date "$(date) - $ago seconds" +%m%d%H%M.%S)
        touch -m -t $mtime $POMO
    fi
}

function pomo_stat {
    # Return number of seconds since start of pomo block (work+break cycle).
    running=$(cat $POMO)
    if [[ -z $running ]]; then
        pomo_start=$(stat -c +%Y $POMO)
        now=$(date +%s)
        running=$((now-pomo_start))
    fi
    echo $running
}

function pomo_clock {
    # Print out how much time is remaining in block.
    # WMM:SS indicates MM:SS left in the work block.
    # BMM:SS indicates MM:SS left in the break block.
    pomo_update
    running=$(pomo_stat)
    left=$(( WORK_TIME*60 - running ))
    if [[ $left -lt 0 ]]; then
        left=$(( left + BREAK_TIME*60 ))
        prefix=B
    else
        prefix=W
    fi
    pomo_ispaused && prefix=P$prefix
    min=$(( left / 60 ))
    sec=$(( left - 60*min ))
    printf "%2s%02d:%02d" $prefix $min $sec
}

# TODO:
# + expose
#   - start
#   - stop
#   - pause
#   - restart
#   - clock
#   - usage
# + test pause+restart
# + README
# + github
# + zenity/notify daemon

#pomo_start
#while true; do
#    pomo_clock
#    echo
#    sleep 1
#done
