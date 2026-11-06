#!/usr/bin/env bats

function setup() {
    POMO_DIR=$(mktemp --directory --tmpdir="$BATS_RUN_TMPDIR")
    export POMO_DIR
    export POMO_FILE=$POMO_DIR/pomo
    export POMO_CONFIG=$POMO_DIR/pomo.cfg
    source pomo.sh
}

function teardown() {
    rm -rf "$POMO_DIR"
}

# Test helpers
function _pomo_clock_helper() {
    # Mock stat so no timing issue around checking the time of POMO_FILE.
    started_at=$1
    function pomo_stat() { echo "$started_at"; }
    export -f pomo_stat
    run pomo_clock
}

function _pomo_msg_helper() {
    expected_duration=$1
    # duplicate first fake stat time as pomo_msg calls pomo_update once at initialisation.
    stat_times=( "$2" "${@:2}" )
    # Set iteration in a file as pomo_msg is run by BATS in a subshell.
    iteration_file=$(mktemp --tmpdir="$BATS_RUN_TMPDIR")
    echo 0 > "$iteration_file"
    function pomo_stat() {
        stat_iteration=$(cat "$iteration_file")
        echo "${stat_times[$stat_iteration]}"
        echo $((stat_iteration+1)) > "$iteration_file"
    }
    run pomo_start
    SECONDS=0
    run pomo_msg
    [[ $SECONDS -ge $expected_duration && $SECONDS -le $((expected_duration + 1)) ]]
}

# Mocks
function notify-send() {
    # Mock notify-send to echo.
    # We set the app-name to notify send using -a, which is not a valid option
    # for echo. Remove the flag and pass everything (app name and message) to
    # echo.
    shift
    echo "$@"
}

@test "pomo_start creates file" {
    [[ ! -e $POMO_FILE ]]
    run pomo_start
    [[ -e $POMO_FILE ]]
}

@test "pomo_stop removes file" {
    run ./pomo.sh start
    [[ -e $POMO_FILE ]]
    run pomo_stop
    [[ ! -e $POMO_FILE ]]
}

@test "pomo_clock when stopped returns blank" {
    run pomo_clock
    [[ "$output" == "  --:--" ]]
}

@test "pomo_ispaused is true when paused" {
    run pomo_start
    run pomo_pause
    run pomo_ispaused
    [[ "$status" -eq 0 ]]
}

@test "pomo_ispaused is false when started" {
    run pomo_start
    run pomo_ispaused
    [[ "$status" -eq 1 ]]
}

@test "pomo_ispaused is false when stopped" {
    run pomo_start
    run pomo_stop
    run pomo_ispaused
    [[ "$status" -eq 1 ]]
}

@test "pomo_isstopped is true when stopped" {
    run pomo_start
    run pomo_stop
    run pomo_isstopped
    [[ "$status" -eq 0 ]]
}

@test "pomo_isstopped is true before first run of pomo" {
    run pomo_isstopped
    [[ "$status" -eq 0 ]]
}

@test "pomo_isstopped is false when started" {
    run pomo_start
    run pomo_isstopped
    [[ "$status" -eq 1 ]]
}

@test "pomo_isstopped is false when paused" {
    run pomo_start
    run pomo_pause
    run pomo_isstopped
    [[ "$status" -eq 1 ]]
}

@test "pomo_clock when started shows time remaining in running block" {
    run pomo_start
    _pomo_clock_helper 52
    [[ "$output" =~ " W24:08" ]]
}

@test "pomo_clock when started and paused shows time remaining in running block" {
    run pomo_start
    run pomo_pause
    _pomo_clock_helper 52
    [[ "$output" =~ "PW24:08" ]]
}

@test "pomo_clock when started shows time remaining in break block" {
    run pomo_start
    _pomo_clock_helper 1565
    [[ "$output" =~ " B03:55" ]]
}

@test "pomo_clock when started and paused shows time remaining in break block" {
    run pomo_start
    run pomo_pause
    _pomo_clock_helper 1565
    [[ "$output" =~ "PB03:55" ]]
}

@test "pomo_set creates a timestamp" {
    now=$(${DATE_CMD} +%s)
    offset=33
    run pomo_stamp $offset
    run "${STAT_CMD}" -c %Y "$POMO"
    [[ "$output" -eq $((now - offset)) ]]
}

@test "pomo_pause stops and starts the clock" {
    run pomo_stamp 1200
    run pomo_pause
    sleep 2
    run pomo_stat
    [[ "$output" -eq 1200 ]]
    run pomo_pause
    sleep 2
    run pomo_stat
    [[ "$output" -eq 1202 ]]
}

@test "pomo_pause creates file if it was stopped before" {
    run pomo_start
    run pomo_stop
    run pomo_pause
    [[ -e $POMO_FILE ]]
}

@test "pomo_pause creates file before first run of pomo" {
    [[ ! -e $POMO_FILE ]]
    run pomo_pause
    [[ -e $POMO_FILE ]]
}

@test "pomo_update does not update the POMO file if not required" {
    run pomo_stamp 33
    run "${STAT_CMD}" -c %Y "$POMO"
    t1=$output
    run pomo_update
    run "${STAT_CMD}" -c %Y "$POMO"
    t2=$output
    [[ "$t1" -eq "$t2" ]]
}

@test "pomo_update updates the POMO file if required" {
    block_time=$(( (WORK_TIME+BREAK_TIME)*60  ))
    run pomo_stamp $(( block_time + 50 ))
    run "${STAT_CMD}" -c %Y "$POMO"
    t1=$output
    run pomo_update
    run "${STAT_CMD}" -c %Y "$POMO"
    t2=$output
    [[ "$(( t1 + block_time))" -eq "$t2" ]]
}

@test "message is sent using notify-send if found" {
    test_msg="test message"
    run send_msg "$test_msg"
    [[ "$output" == "Pomodoro $test_msg" ]]
}

@test "message is sent using echo if notify-send not found" {
    function command() { return 1; }
    export -f command
    test_msg="test message"
    run send_msg "$test_msg"
    [[ "$output" == "$test_msg" ]]
}

@test "pomo_msg sends message about end of work block" {
    _pomo_msg_helper 2 $((WORK_TIME*60-2)) $((WORK_TIME*60))
    [[ "$output" == "Pomodoro End of a work period. Time for a break!" ]]
}

@test "pomo_msg sends message about end of break block" {
    _pomo_msg_helper 2 $(( (WORK_TIME+BREAK_TIME)*60-2)) $(( (WORK_TIME+BREAK_TIME)*60))
    [[ "$output" == "Pomodoro End of a break period. Time for work!" ]]
}

@test "pomo_msg handles timestamp update before it can send the end of break message 1" {
    _pomo_msg_helper 2 $(( (WORK_TIME+BREAK_TIME)*60-2)) 0
    [[ "$output" == "Pomodoro End of a break period. Time for work!" ]]
}

@test "pomo_msg handles timestamp update before it can send the end of break message 2" {
    _pomo_msg_helper 2 $(( (WORK_TIME+BREAK_TIME)*60-2)) 1
    [[ "$output" == "Pomodoro End of a break period. Time for work!" ]]
}

@test "pomo_msg handles being paused" {
    _pomo_msg_helper 3 $((WORK_TIME*60-2)) $((WORK_TIME*60-1)) $((WORK_TIME*60))
    [[ "$output" == "Pomodoro End of a work period. Time for a break!" ]]
}

@test "config file can set POMO_PREFIX_CMDS" {
    echo 'POMO_PREFIX_CMDS="true"' > "$POMO_CONFIG"
    source pomo.sh
    [[ "$DATE_CMD" == "gdate" ]]
    [[ "$STAT_CMD" == "gstat" ]]
}

@test "pomo_ispaused produces no stderr when stopped" {
    run pomo_ispaused
    [[ "$status" -eq 1 ]]
    [[ "$output" == "" ]]
}

@test "pomo_pause after multiple cycles does not produce negative clock" {
    pomo_stamp 4200
    pomo_pause
    run pomo_clock
    [[ ! "$output" =~ "-" ]]
    [[ "$output" =~ "PW15:00" ]]
}

@test "pomo_stamp creates parent directory if it does not exist" {
    POMO="$POMO_DIR/nested/sub/pomo"
    run pomo_stamp 100
    [[ "$status" -eq 0 ]]
    [[ -e "$POMO" ]]
}

@test "pomo_msg returns 1 if pomo is stopped while waiting" {
    pomo_start
    iteration_file=$(mktemp --tmpdir="$BATS_RUN_TMPDIR")
    echo 0 > "$iteration_file"
    function pomo_stat() {
        stat_iter=$(cat "$iteration_file")
        if [[ $stat_iter -eq 0 ]]; then
            echo 100
        else
            rm -f "$POMO"
            echo 0
        fi
        echo $((stat_iter + 1)) > "$iteration_file"
    }
    function sleep() {
        loop_count=$(cat "$iteration_file")
        if [[ $loop_count -gt 2 ]]; then
            exit 42
        fi
    }
    export -f sleep
    run pomo_msg
    [[ "$status" -eq 1 ]]
}

@test "pomo.sh with invalid action returns exit code 1" {
    run ./pomo.sh invalid_action
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Unknown option/action: invalid_action." ]]
}

@test "pomo.sh -h start displays usage and does not start timer" {
    run ./pomo.sh -h start
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "pomo.sh - a simple Pomodoro timer." ]]
    [[ ! -e "$POMO_FILE" ]]
}

@test "sourcing pomo.sh directly produces no stdout or stderr" {
    run bash -c "source ./pomo.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "" ]]
}
