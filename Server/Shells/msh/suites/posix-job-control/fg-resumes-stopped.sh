# msh-profile: posix-job-control
# msh-run: file
set -m
sleep 1 &
pid=$!
kill -TSTP "$pid"
jobs -l
fg > fg.out
grep "sleep 1" fg.out || exit 3
