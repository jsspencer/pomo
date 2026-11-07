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

#--- Pomodoro functions ---

function pomo_start {
    # Start new pomo block (work+break cycle).
    rm -f "$POMO" "${POMO}.session"
    test -e "$(dirname -- "$POMO")" || mkdir -p "$(dirname -- "$POMO")"
    touch "$POMO"
    echo "$$ $RANDOM $(${DATE_CMD} +%s 2>/dev/null)" > "${POMO}.session"
}

function pomo_isstopped {
    # Return 0 if stopped, 1 otherwise.
    # pomo.sh is stopped if the POMO file does not exist.
    [[ ! -e "$POMO" ]]
    return $?
}

function pomo_stop {
    # Stop pomo cycles.
    rm -f "$POMO" "${POMO}.session"
}

function pomo_stamp {
    # Set the timestamp of the POMO file to $1 seconds ago.
    local ago=$1
    local mtime=$(${DATE_CMD} --date "@$(( $(${DATE_CMD} +%s) - ago))" +%Y%m%d%H%M.%S)
    test -e "$(dirname -- "$POMO")" || mkdir -p "$(dirname -- "$POMO")"
    :> "$POMO" # erase saved time stamp due to a pause.
    touch -m -t "$mtime" "$POMO"
}

function pomo_ispaused {
    # Return 0 if paused, 1 otherwise.
    # pomo.sh is paused if the POMO file contains any information.
    [[ -s "$POMO" ]]
}

function pomo_pause {
    # Toggle the pause status on the POMO file.
    pomo_update
    local running=$(pomo_stat)
    local block_time=$(( (WORK_TIME+BREAK_TIME)*60 ))
    if [[ $block_time -gt 0 && $running -ge $block_time ]]; then
        running=$(( running % block_time ))
    fi
    if pomo_isstopped || pomo_ispaused; then
        # Restart a stopped/paused pomo block by updating the time stamp of the POMO
        # file.
        pomo_stamp "$running"
    else
        # Pause a pomo block.
        echo "$running" > "$POMO"
    fi
}

function pomo_update {
    # Update the time stamp on POMO a new cycle has started.
    pomo_isstopped && return
    pomo_ispaused && return
    local running=$(pomo_stat)
    local block_time=$(( (WORK_TIME+BREAK_TIME)*60 ))
    if [[ $running -ge $block_time ]]; then
        local ago=$(( running % block_time )) # We should've started the new cycle a while ago?
        local mtime=$(${DATE_CMD} --date "@$(( $(${DATE_CMD} +%s) - ago))" +%Y%m%d%H%M.%S)
        touch -m -t "$mtime" "$POMO"
    fi
}

function pomo_stat {
    # Return number of seconds since start of pomo block (work+break cycle).
    local running=0
    [[ -e "$POMO" ]] && running=$(cat "$POMO")
    if [[ -z $running ]]; then
        local pomo_start=$(${STAT_CMD} -c %Y "$POMO")
        local now=$(${DATE_CMD} +%s)
        running=$((now-pomo_start))
    fi
    echo $running
}

function pomo_clock {
    # Print out how much time is remaining in block.
    # WMM:SS indicates MM:SS left in the work block.
    # BMM:SS indicates MM:SS left in the break block.
    if ! pomo_isstopped; then
        pomo_update
        local running=$(pomo_stat)
        local block_time=$(( (WORK_TIME+BREAK_TIME)*60 ))
        if [[ $block_time -gt 0 && $running -ge $block_time ]]; then
            running=$(( running % block_time ))
        fi
        local left=$(( WORK_TIME*60 - running ))
        local prefix
        if [[ $left -lt 0 ]]; then
            left=$(( left + BREAK_TIME*60 ))
            prefix=B
        else
            prefix=W
        fi
        pomo_ispaused && prefix=P$prefix
        local min=$(( left / 60 ))
        local sec=$(( left - 60*min ))
        printf "%2s%02d:%02d\n" $prefix $min $sec
    else
        printf "  --:--\n"
    fi
}

function pomo_status {
    while true; do
        pomo_clock
        sleep 1
    done
}

function pomo_msg {
    # Send a message using the GUI or console at the end of the next
    # work or break block. Returns 1 if the session is not running or
    # is stopped mid-cycle.
    [[ -e "$POMO" ]] || return 1
    pomo_update
    if [[ ! -f "${POMO}.session" ]]; then
        echo "$$ $RANDOM $(${DATE_CMD} +%s 2>/dev/null)" > "${POMO}.session"
    fi
    local initial_session=$(cat "${POMO}.session" 2>/dev/null)
    local running=$(pomo_stat)
    local block_time=$(( (WORK_TIME+BREAK_TIME)*60 ))
    local left
    local work
    local stat
    while true; do
        [[ -e "$POMO" ]] || return 1
        if [[ $block_time -gt 0 && $running -ge $block_time ]]; then
            running=$(( running % block_time ))
        fi
        left=$(( WORK_TIME*60 - running ))
        work=true
        if [[ $left -lt 0 ]]; then
            left=$(( left + BREAK_TIME*60 ))
            work=false
        fi
        [[ $left -lt 0 ]] && left=0
        sleep $left
        [[ -e "$POMO" ]] || return 1
        # Check if the POMO session was stopped or restarted while sleeping.
        local current_session=$(cat "${POMO}.session" 2>/dev/null)
        [[ -n "$current_session" && "$current_session" == "$initial_session" ]] || return 1
        # pomo_stat is time from the start of the work+block cycle.
        # 1. If switching from work->break then stat >= running + left.
        # 2. If switching from break->work then either
        #    stat >= running + left (haven't updated timestamp) or
        #    stat < running (have just updated the timestamp from a
        #    separate pomo call, e.g. using pomo status).
        stat=$(pomo_stat)
        [[ $stat -ge $(( running + left )) ]] && break
        $work || { [[ $stat -lt $running ]] && break; }
        running=$stat
    done
    if [[ $(( stat - running - left )) -le 1 ]]; then
        if $work; then
            $MSG_CALLBACK 0  # end of work block
        else
            $MSG_CALLBACK 1  # end of break block
        fi
    fi
    return 0
}

function pomo_notify {
    while true; do
        if pomo_msg; then
            # sleep for a second so that the timestamp of POMO is not the
            # current time (i.e. allow next unit to start).
            sleep 1
        else
            sleep 60
        fi
    done
}

function pomo_msg_callback {
    local block_type=$1
    local msg
    if [[ $block_type -eq 0 ]]; then
        msg='End of a work period. Time for a break!'
    elif [[ $block_type -eq 1 ]]; then
        msg='End of a break period. Time for work!'
    else
        echo "Unknown block type"
        return 1
    fi
    send_msg "$msg"
}

function send_msg {
    if [ "$(uname)" == "Darwin" ]; then
        osascript -e "display notification \"${1//\"/\\\"}\" with title \"Pomodoro\"" > /dev/null 2>&1
    elif command -v notify-send &> /dev/null; then
        notify-send -a "Pomodoro" "${1}"
    else
        echo "${1}"
    fi
}

#--- Help ---

function pomo_usage {
    # Print out usage message.
    cat <<END
pomo.sh [-h] [-c file] [start | stop | pause | clock | status | notify | usage]

pomo.sh - a simple Pomodoro timer.

Options:

-c file
    Specify the path to the config file containing variable definitions.
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
    Raise a notification at the end of every Pomodoro work and break block in
    an infinite loop.  Requires notify-send (linux) or osascript (OS X).
status
    Continuously print the current status of the Pomodoro timer once a second,
    in the same format as the clock action.
usage
    Print this usage message.

Note that the notify and status actions (unlike all others) do not terminate and
are best run in the background.

Environment variables:

POMO_CONFIG
    Location of the config file. Default: \$XDG_CONFIG_HOME/pomo.cfg. Can also
    be set using the -c option.
POMO_FILE
    Location of the Pomodoro file used to store the duration of the Pomodoro
    period (mostly using timestamps).  Multiple Pomodoro timers can be run by
    using different files.  Default: \$HOME/.local/share/pomo.
POMO_WORK_TIME
    Duration of the work period in minutes.  Default: 25.
POMO_BREAK_TIME
    Duration of the break period in minutes.  Default: 5.
POMO_MSG_CALLBACK
   Function to call at the end of a period, with argument of 0 for end of a
   work period and 1 for the end of a break period. Default: pomo_msg_callback.

Environment variables other than POMO_CONFIG can also be set in POMO_CONFIG,
which is sourced if it exists.
END
}

#--- Configuration (can be set via environment variables or config file) ---

action=
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
config=${POMO_CONFIG:-"$config_home/pomo.cfg"}

#--- Command-line interface ---

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    while getopts "hc:" arg; do
        case $arg in
            c)
                config=$OPTARG
                ;;
            h|?)
                action=usage
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z $action ]]; then
        actions="start stop pause clock usage notify status"
        for act in $actions; do
            if [[ $act == "$1" ]]; then
                action=$act
                break
            fi
        done
    fi
fi

[[ -e ${config} ]] && source "${config}"
POMO=${POMO_FILE:-"$HOME/.local/share/pomo"}
WORK_TIME=${POMO_WORK_TIME:-25}
BREAK_TIME=${POMO_BREAK_TIME:-5}
MSG_CALLBACK=${POMO_MSG_CALLBACK:-pomo_msg_callback}

#--- Check environment ---
if [ "$(uname)" == "Darwin" ] || [ "${POMO_PREFIX_CMDS}" == "true" ]; then
    # Use GNU coreutils installed with a prefix
    DATE_CMD="gdate"
    STAT_CMD="gstat"
else
    DATE_CMD="date"
    STAT_CMD="stat"
fi

#--- Run! ---

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -n $action ]]; then
        pomo_"$action"
    else
        [[ $# -gt 0 ]] && echo "Unknown option/action: $1." || echo "Action not supplied."
        pomo_usage
        exit 1
    fi
fi
