pomo.sh
=======

pomo.sh is a simple `Pomodoro
<http://en.wikipedia.org/wiki/Pomodoro_Technique>`_ timer written in bash with
minimal dependencies.  It is designed to be easy to use from the command-line
and integrates nicely into status bar such as `xmobar <http://projects.haskell.org/xmobar/>`_.

Installation
------------

None necessary.  Either place pomo.sh on your PATH or run it by specifying the
full path.

Usage
-----

pomo.sh [-h] [start | stop | pause | restart | clock | notify | usage]

Options:

\-h
    Print usage message.

Actions:

start
    Start Pomodoro timer.
stop
    Stop Pomodoro timer.
pause
    Pause Pomodoro timer.
restart
    Restart a paused Pomodoro timer.
clock
    Print how much time (minutes and seconds) is remaining in the current
    Pomodoro cycle.  A prefix of B indicates a break period, a prefix of
    W indicates a work period and a prefix of P indicates the current period is
    paused.
notify
    Raise a notification at the end of every Pomodoro work and break block (requires
    notify-send).   Note that this action (unlike all others) does not
    terminate and is best run in the background.
usage
    Print this usage message.

Environment variables:

POMO_FILE
    Location of the Pomodoro file used to store the duration of the Pomodoro
    period (mostly using timestamps).  Multiple Pomodoro timers can be run by
    using different files.  Default: $HOME/.local/share/pomo.
POMO_WORK_TIME
    Duration of the work period in minutes.  Default: 25.
POMO_BREAK_TIME
    Duration of the break period in minutes.  Default: 5.

Examples
--------

To start a new Pomodoro session, pause and stop a running Pomodoro session respectively::

$ pomo.sh start
$ pomo.sh pause
$ pomo.sh stop

To see how much time is left in the current Pomodoro block::

$ pomo.sh clock

pomo.sh can also send notifications about the end of work and break blocks
using notification-daemon and send-notify.  This involves pomo.sh sleeping until the end of a block and so is best run in the background::

$ pomo.sh notify &

The clock command is ideal for running from inside xmobar, e.g. in the xmobar
configuration file::

    Config {
        commands = [
            -- rest of commands
            , Run Com "pomo.sh" ["clock"] "pomo" 10"
            ]
        -- rest of config
    }

The output of the clock command can then be inserted into the xmobar template
using ``%pomo%``.

Dependencies
------------

bash, GNU coreutils (cat, cut, date, printf, sleep, stat, touch, wc).  The notify action also requires  send-notify (supplied by libnotify) and an implementation of notification-daemon.

License
-------

MIT.

See also
--------

`Pymodoro <https://github.com/dattanchu/pymodoro>`_ contains many more features but
I wanted something a little simpler.
