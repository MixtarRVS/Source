# msh-source: smoosh/tests/shell/builtin.continue.lexical.test
# msh-profile: posix
# msh-run: eval
cnt() { continue 5 2>/dev/null; echo post; }
i=0; while [ $i -lt 5 ]; do echo $i; : $((i+=1)); cnt; echo after; done