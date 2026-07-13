# msh-source: smoosh/tests/shell/builtin.times.ioerror.test
# msh-profile: posix
# msh-run: eval
exec 3>&1
(
  trap "" PIPE
  i=0
  while [ "$i" -lt 10000 ]; do
    i=$((i + 1))
  done
  command times
  echo ?=$? >&3
) | :
