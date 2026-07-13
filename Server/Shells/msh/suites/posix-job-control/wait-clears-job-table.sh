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
jobs -l
kill %1 %2
wait
