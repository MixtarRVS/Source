# msh-profile: posix-job-control
# msh-run: file
set -m
sleep 5 &
pid1=$!
sleep 6 &
pid2=$!
jobs %sleep 2> jobs-ambiguous.err
status=$?
grep "ambiguous" jobs-ambiguous.err || exit 3
test "$status" -ne 0 || exit 4
kill "$pid1" "$pid2"
wait "$pid1" "$pid2" 2>/dev/null
true
