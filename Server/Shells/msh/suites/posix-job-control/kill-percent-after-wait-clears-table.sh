# msh-profile: posix-job-control
# msh-run: file
sleep 5 &
pid1=$!
sleep 6 &
pid2=$!
kill "$pid1" "$pid2"
wait
set -m
sleep 5 &
pid3=$!
sleep 6 &
pid4=$!
start=$(date "+%s")
sleep 1
kill %1 %2 || exit 3
wait
stop=$(date "+%s")
elapsed=$((stop - start))
test "$elapsed" -lt 3 || exit 4
