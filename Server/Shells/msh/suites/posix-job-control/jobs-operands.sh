# msh-profile: posix-job-control
# msh-run: file
set -m
sleep 5 &
pid1=$!
sleep 6 &
pid2=$!
jobs %1 > jobs-1.out
grep "sleep 5" jobs-1.out || exit 3
jobs %2 > jobs-2.out
grep "sleep 6" jobs-2.out || exit 4
jobs -p %1 > jobs-p1.out
grep "^$pid1$" jobs-p1.out || exit 5
jobs -p %2 > jobs-p2.out
grep "^$pid2$" jobs-p2.out || exit 6
kill "$pid1" "$pid2"
wait "$pid1" "$pid2" 2>/dev/null
true
