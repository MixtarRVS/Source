# msh-source: smoosh/tests/shell/semantics.subshell.break.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01773.html
for x in a b
  do
    (
      for y in c d
      do
        break 2
      done
      echo $x
    )
  done 