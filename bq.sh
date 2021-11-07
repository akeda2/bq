#!/bin/bash

#This is a fork of sitaramc/bq

# simple task queue; output files are in /dev/shm/bq-$USER.  Uses no locks;
# use 'mv' command, which is atomic (within the same file system anyway) to
# prevent contention.
# ref: https://rcrowley.org/2010/01/06/things-unix-can-do-atomically.html

# run "bq -w" once to start a worker

# run "bq command [args...]" to put tasks in queue

# run "bq" to view the output directory using vifm, unless $BQ_FILEMANAGER is set

# see bq.mkd for more (e.g., using different queues, increasing/decreasing the
# number of workers in a queue, etc.)

#Slightly modded by me (akeda) to always use "mc" instead of "vifm"

# ----------------------------------------------------------------------

die() { echo "$@" >&2; exit 1; }

[ "$1" = "-h" ] && {
    cat <<-EOF
_-:*'BQ'*:-_ Forked by akeda: https://github.com/akeda2/bq.git
	Example usage:
	   Start a worker
	    bq -w
           Start a worker in another queue
            bq -q queue -w
           Start n workers
            bq (-q queue) -w -n n
           Report amount of current workers in queue
            bq (-q queue) -g
           Stop a worker process
            bq -k
           Stop all workers
            bq -ka
           Stop all workers in a queue
            bq -q queue -ka
            
	   Submit a job
	    bq some-command arg1 arg2 [...]
	   Check status
	    bq                              # uses mc as the file manager
	    export BQ_FILEMANAGER=mc; bq    # env var overrides default
	    # you can only run one simple command; if you have a command with
	    # shell meta characters (;, &, &&, ||, >, <, etc), do this:
	    bq bash -c 'echo hello; echo there >junk.\$RANDOM'
	EOF
    exit 1
}

# ----------------------------------------------------------------------
# SETUP

TMP=/dev/shm
[ -d $TMP ] || TMP=/tmp

# I doubt I will ever use multiple Qs, but it's easy enough to implement
Q=default
[ "$1" = "-q" ] && {
    [ -z "$2" ] || [[ "$2" == -* ]]&& die "-q needs a queue name"
    Q=$2; shift; shift
}
[ -z "$QDIR" ] && export QDIR=$TMP/bq-$USER-$Q
mkdir -p $QDIR/w
mkdir -p $QDIR/q
mkdir -p $QDIR/OK

# LOOK FOR OLD WORKERS
for pros in $QDIR/w/*; do
	if [ -f "$pros" ]; then
		bname="${pros##*/}"
        	woext="${bname%.*}"
        	ext="${bname##*.}"
		if [ $ext != "exited" ] && [ $((ps "$woext") | wc -l) -lt 2 ]; then
			echo "Found orphan worker: $pros"
			rm "$pros"
		fi
	fi
done

# ----------------------------------------------------------------------
# WORK 1 TASK

_work_1() {
    ID=$1

    # "claim" the task in q by renaming q/$ID to a name that contains our own PID
    mv q/$ID $ID.running.$$ 2>/dev/null

    # if the "claim" succeeded, we won the race to run the task
    if [ -f $ID.running.$$ ]
    then
        # get the command line arguments and run them
        readarray -t cmd < $ID.running.$$

        # the first line is the directory to be in; shift that out first
        newpwd="${cmd[0]}"
        cmd=("${cmd[@]:1}")

        # log the command for debugging later
        echo -n "cd $newpwd; ${cmd[@]}" >> w/$$

        # the directory may have disappeared between submitting the
        # job and running it now.  Catch that by trying to cd to it
        cd "$newpwd" || cmd=(cd "$newpwd")
        # if the cd failed, we simply replace the actual command with
        # the same "cd", and let it run and catch the error.  Bit of a
        # subterfuge, actually, but it works fine.

        # finally we run the task.  Note that our PWD now is NOT $QDIR, so
        # the two redirected filenames have to be fully qualified
        "${cmd[@]}" > $QDIR/$ID.1 2> $QDIR/$ID.2
        ec=$?

        cd $QDIR
        mv $ID.running.$$ $ID.exitcode=$ec
        [ "$ec" = "0" ] && mv $ID.* OK
        echo " # $ec" >> w/$$
#        notify-send "`wc -l w/$$`" "`tail -1 w/$$`"
    fi
}

# ----------------------------------------------------------------------
# START AND DAEMONISE A WORKER

# How many workers are active?
how_many_w (){
    echo `cd $QDIR/w; ls | grep -v exited | wc -l`
}


# '-w' starts a worker; each worker runs one job at a time, so if you want
# more jobs to run simultaneously, run this multiple times!
[ "$1" = "-w" ] && [ -z "$2" ] && {

    # if the user is starting a worker, any existing kill commands don't apply
    rm -f $QDIR/q/0.*.-k

    # daemonize
    nohup "$0" -w $QDIR >> $QDIR/nohup.out &

    # remind the user how many workers he has started, in case he forgot
    sleep 0.5   # wait for the other task to kick off
    echo `cd $QDIR/w; ls | grep -v exited | wc -l` workers running
    exit 0
}

#Start several workers

#If -n $3 is not specified, we count the cpu-cores
if [ "$1" == "-w" ] && [ "$2" == "-n" ]; then
	if [ -z "$3" ]; then
		n="$(nproc)"
		echo "n cpus = $n"
	else
		n="$3"
	fi

	ti=$(how_many_w)

    	while [ $ti -lt $n ]; do
		rm -f $QDIR/q/0.*.-k
		nohup "$0" -w $QDIR > $QDIR/nohup.out_$ti &
		sleep 2   # wait for the other task to kick off
		ti=$(how_many_w)
    	done
    	exit 0
fi

[ "$1" = "-g" ] && [ -z "$2" ] && {
    # remind the user how many workers he has started, in case he forgot
    echo $(how_many_w)
    exit 0
}

# ----------------------------------------------------------------------
# STOP A WORKER

[ "$1" = "-k" ] && [ -z "$2" ] && {
    touch $QDIR/q/0.$$.-k
    # starting with a "0" assures that in an "ls" this file will come before
    # any normal task files (which all start with `date +%s`).  The contents
    # don't matter, since it won't be "executed" in the normal manner.
    exit 0
}

# STOP ALL WORKERS

[ "$1" = "-ka" ] && [ -z "$2" ] && {
    ta=$(how_many_w)
    tk=0
    while [ "$tk" -le "$ta" ]; do
	touch $QDIR/q/0.$$$tk.-k
	tk=$(( $tk + 1 ))
    done
    exit 0
}

# ----------------------------------------------------------------------
# WORKER LOOP

[ "$1" = "-w" ] && {

    touch $QDIR/w/$$

    while :
    do
        cd $QDIR

        ID=`cd q; ls | head -1`
        # if nothing is waiting in q, go to sleep, but use inotifywait so you
        # get woken up immediately if a new task lands
        [ -z "$ID" ] && {
            inotifywait -q -t 60 -e create q >/dev/null
            continue
            # whether we got an event or just timed out, we just go back round
        }

        # note there is still a bit of a race here.  If tasks were submitted
        # *between* the "ID=" and the "inotifywait" above, they will end up
        # waiting 60 seconds before they get picked up.  Hopefully that's a
        # corner case, and anyway at worst it only causes a delay.

        # handle exit, again using the "mv is atomic" principle
        [[ $ID == 0.*.-k ]] && {
            mv q/$ID $ID.exiting.$$
            [ -f     $ID.exiting.$$ ] && {
                mv w/$$ w/$$.exited
                rm $ID.exiting.$$
                exit 0
            }
        }

        # ok there was at least one task waiting; try to "work" it
        _work_1 $ID
    done

    # we should never get here
    touch $QDIR/worker.$$.unexpected-error
}

# ----------------------------------------------------------------------
# STATUS

# examine the output directory using $BQ_FILEMANAGER (defaulting to vifm)
[ -z "$1" ] && exec sh -c "${BQ_FILEMANAGER:-mc} $QDIR"

# ----------------------------------------------------------------------

# some command was given; add it to the queue
ID=`date +%s`.$$.${1//[^a-z0-9_.-]/}
pwd                 > $QDIR/q/$ID
printf "%s\n" "$@" >> $QDIR/q/$ID
