# msh-profile: posix-job-control
# msh-run: file
set -m
start=$(date "+%s")
sleep 3 &
pid=$!
kill -TSTP "$pid"
jobs -l
fg > output
stop=$(date "+%s")
elapsed=$((stop - start))
test "$elapsed" -ge 3 || exit 2
grep "sleep 3" output || exit 3
