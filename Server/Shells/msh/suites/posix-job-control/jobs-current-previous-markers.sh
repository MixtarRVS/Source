# msh-profile: posix-job-control
# msh-run: file
set -m
sleep 5 &
pid1=$!
sleep 6 &
pid2=$!
jobs -l > jobs-markers.out
grep "^\[2\] + " jobs-markers.out || exit 3
grep "^\[1\] - " jobs-markers.out || exit 4
jobs %% > jobs-current.out
grep "sleep 6" jobs-current.out || exit 5
jobs %- > jobs-previous.out
grep "sleep 5" jobs-previous.out || exit 6
bg %+ > bg-current.out
grep "^\[2\] + " bg-current.out || exit 7
kill "$pid1" "$pid2"
wait "$pid1" "$pid2" 2>/dev/null
true
