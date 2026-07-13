# msh-profile: posix-job-control
# msh-run: file
set -m
sleep 5 &
pid=$!
jobs %sleep > jobs-prefix.out
grep "sleep 5" jobs-prefix.out || exit 3
jobs %?leep > jobs-substring.out
grep "sleep 5" jobs-substring.out || exit 4
kill "$pid"
wait "$pid" 2>/dev/null
true
