# msh-profile: posix-job-control
# msh-run: file
set -m
sleep 5 &
pid=$!
jobs -p > jobs-p.out
grep "^$pid$" jobs-p.out || exit 3
kill "$pid"
wait "$pid" 2>/dev/null
true
