# msh-profile: posix-job-control
# msh-run: file
set -m
sh -c 'sleep 2; printf BAD > left.out' | sleep 5 &
kill %1 || exit 2
wait
sleep 3
if [ -f left.out ]; then
    exit 3
fi
exit 0
