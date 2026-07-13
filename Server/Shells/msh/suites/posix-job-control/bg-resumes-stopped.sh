# msh-profile: posix-job-control
# msh-run: file
set -m
sleep 2 &
pid=$!
kill -TSTP "$pid"
jobs -l
bg > bg.out
grep "sleep 2" bg.out || exit 3
wait
