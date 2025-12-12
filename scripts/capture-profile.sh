# Arguments: 
# $1 - process to run

PID=`pgrep -x $1`
if [ -z "$PID" ]; then
    echo "No running emulator found"
    exit
fi

rm profile.pb.gz
sudo dtrace -x ustackframes=100 -n "profile-97 /pid == $PID && arg1/ { @[ustack()] = count(); } tick-60s { exit(0); }" | dtraceStacksToPprof
echo "Profile captured successfully"
