# msh-source: smoosh/tests/shell/builtin.break.lexical.test
# msh-profile: posix
# msh-run: eval
brk() { break 5 2>/dev/null; echo post; }
i=0; while [ $i -lt 5 ]; do echo $i; brk; : $((i+=1)); done