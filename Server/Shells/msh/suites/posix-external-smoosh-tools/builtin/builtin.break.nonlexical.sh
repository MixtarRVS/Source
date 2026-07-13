# msh-source: smoosh/tests/shell/builtin.break.nonlexical.test
# msh-profile: posix
# msh-run: eval
set -o nonlexicalctrl 2>/dev/null
brk() { break 5 2>/dev/null; echo post; }
i=0; while [ $i -lt 5 ]; do echo $i; brk; : $((i+=1)); done