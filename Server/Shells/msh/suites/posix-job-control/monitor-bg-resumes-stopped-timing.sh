# msh-profile: posix-job-control
# msh-run: file
set -m
start=$(date "+%s")
sleep 3 &
pid=$!
kill -TSTP "$pid"
jobs -l
bg > output
grep "[1]" output || exit 3
grep "sleep 3" output || exit 4
wait
stop=$(date "+%s")
elapsed=$((stop - start))
test "$elapsed" -ge 3 || exit 5
