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

#--- pomo.sh ---

# pomo.sh is a simple Pomodoro timer.  It works by creating a file ($POMO) and
# inspecting the modification timestamp of that file to determine for how long
# a Pomodoro block has been running.  Pausing a Pomodoro block works by storing
# how long the Pomodoro block has been running in the $POMO file.  A paused
# Pomodoro block can then be resumed by updating the modification timestamp of
# the POMO file accordingly.

#--- Check environment ---
if [ "$(uname)" == "Darwin" ] || [ "${POMO_PREFIX_CMDS}" == "true" ]; then
    # Use GNU coreutils installed with a prefix
    DATE_CMD="gdate"
    STAT_CMD="gstat"
else
    DATE_CMD="date"
    STAT_CMD="stat"
fi

#--- Configuration (can be set via environment variables) ---

[[ -n $POMO_FILE ]] && POMO=$POMO_FILE || POMO=$HOME/.local/share/pomo

[[ -n $POMO_WORK_TIME ]] && WORK_TIME=$POMO_WORK_TIME || WORK_TIME=25
[[ -n $POMO_BREAK_TIME ]] && BREAK_TIME=$POMO_BREAK_TIME || BREAK_TIME=5

#--- Pomodoro functions ---

function pomo_start {
    # Start new pomo block (work+break cycle).
    test -e $(dirname $POMO) || mkdir $(dirname $POMO)
    touch $POMO
}

function pomo_stop {
    # Stop pomo cycles.
    rm -f $POMO
}

function pomo_ispaused {
    # Return 0 if paused, 1 otherwise.
    # pomo.sh is paused if the POMO file contains any information.
    [[ $(wc -l $POMO | cut -d" " -f1) -gt 0 ]]
    return $?
}

function pomo_pause {
    # Toggle the pause status on the POMO file.
    if pomo_ispaused; then
        # Restart a paused pomo block by updating the time stamp of the POMO
        # file.
        running=$(pomo_stat)

        mtime=$(${DATE_CMD} --date "@$(( $(date +%s) - running))" +%m%d%H%M.%S)
        rm $POMO # erase saved time stamp.
        touch -m -t $mtime $POMO
    else
        # Pause a pomo block.
        running=$(pomo_stat)
        echo $running > $POMO
    fi
}

function pomo_update {
    # Update the time stamp on POMO a new cycle has started.
    running=$(pomo_stat)
    block_time=$(( (WORK_TIME+BREAK_TIME)*60 ))
    if [[ $running -ge $block_time ]]; then
        ago=$(( running % block_time )) # We should've started the new cycle a while ago?
        mtime=$(${DATE_CMD} --date "@$(( $(date +%s) - ago))" +%m%d%H%M.%S)
        touch -m -t $mtime $POMO
    fi
}

function pomo_stat {
    # Return number of seconds since start of pomo block (work+break cycle).
    [[ -e $POMO ]] && running=$(cat $POMO) || running=0
    if [[ -z $running ]]; then
        pomo_start=$(${STAT_CMD} -c +%Y $POMO)
        now=$(${DATE_CMD} +%s)
        running=$((now-pomo_start))
    fi
    echo $running
}

function pomo_clock {
    # Print out how much time is remaining in block.
    # WMM:SS indicates MM:SS left in the work block.
    # BMM:SS indicates MM:SS left in the break block.
    if [[ -e $POMO ]]; then
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
        printf "%2s%02d:%02d\n" $prefix $min $sec
    else
        printf "  --:--\n"
    fi
}

function pomo_status {
    while true; do
        echo $(pomo_clock)
        sleep 1
    done
}

function pomo_notify {
    # Send a message using the GUI or console at the end of each
    # Pomodoro block.  This requires a Pomodoro session to
    # have already been started...
    if [[ -e $POMO ]]; then
        break_end_msg='End of a break period.  Time for work!'
        work_end_msg='End of a work period.  Time for a break!'
        while true; do
            pomo_update
            while true; do
                running=$(pomo_stat)
                left=$(( WORK_TIME*60 - running ))
                work=true
                if [[ $left -lt 0 ]]; then
                    left=$(( left + BREAK_TIME*60 ))
                    work=false
                fi
                sleep $left
                # Check that the block is actually done (i.e. pomo was not
                # paused whilst we were sleeping).
                stat=$(pomo_stat)
                [[ $stat -ge $(( running + left )) ]] && break
            done
            if [[ $(( stat - running - left )) -le 1 ]]; then
                if $work; then
                    send_msg "$work_end_msg"
                else
                    send_msg "$break_end_msg"
                fi
            fi
            # sleep for a second so that the timestamp of POMO is not the
            # current time (i.e. allow next unit to start).
            sleep 1
        done
    fi
}


function send_msg {
    if [ "$(uname)" == "Darwin" ]; then
        osascript -e "tell app \"System Events\" to display dialog \"${1}\"" &> /dev/null
    elif command -v notify-send &> /dev/null; then
        notify-send Pomodoro "${1}"
    else
        echo "${1}"
    fi
}

#--- Help ---

function pomo_usage {
    # Print out usage message.
    cat <<END
pomo.sh [-h] [start | stop | pause | clock | status | notify | usage]

pomo.sh - a simple Pomodoro timer.

Options:

-h
    Print this usage message.

Actions:

start
    Start Pomodoro timer.
stop
    Stop Pomodoro timer.
pause
    Pause a running Pomodoro timer or restart a paused Pomodoro timer.
clock
    Print how much time (minutes and seconds) is remaining in the current
    Pomodoro cycle.  A prefix of B indicates a break period, a prefix of
    W indicates a work period and a prefix of P indicates the current period is
    paused.
notify
    Raise a notification at the end of every Pomodoro work and break block
    (requires notify-send).
status
    Continuously print the current status of the Pomodoro timer once a second,
    the the same format as the clock action.
usage
    Print this usage message.

Note that the notify and status actions (unlike all others) do not terminate and
are best run in the background.

Environment variables:

POMO_FILE
    Location of the Pomodoro file used to store the duration of the Pomodoro
    period (mostly using timestamps).  Multiple Pomodoro timers can be run by
    using different files.  Default: \$HOME/.local/share/pomo.
POMO_WORK_TIME
    Duration of the work period in minutes.  Default: 25.
POMO_BREAK_TIME
    Duration of the break period in minutes.  Default: 5.
END
}

#--- Command-line interface ---

action=
while getopts h arg; do
    case $arg in
        h|?)
            action=usage
            ;;
    esac
done
shift $(($OPTIND-1))

actions="start stop pause clock usage notify status"
for act in $actions; do
    if [[ $act == $1 ]]; then
        action=$act
        break
    fi
done

if [[ -n $action ]]; then
    pomo_$action
else
    [[ $# -gt 0 ]] && echo "Unknown option/action: $1." || echo "Action not supplied."
    pomo_usage
fi
