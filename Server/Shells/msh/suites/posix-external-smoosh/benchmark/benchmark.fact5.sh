# msh-source: smoosh/tests/shell/benchmark.fact5.test
# msh-profile: posix
# msh-run: eval
fact() {
  n=$1
  if [ "$n" -le 0 ]
  then echo 1
  else echo $((n * $(fact $((n-1)) ) ))
  fi
}
fact 5
