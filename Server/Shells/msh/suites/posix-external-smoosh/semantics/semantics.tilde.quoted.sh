# msh-source: smoosh/tests/shell/semantics.tilde.quoted.test
# msh-profile: posix
# msh-run: eval
HOME="weird    times"
printf '%s\n' ~
: >a1
: >a2
: >a3
HOME='a*'
printf '%s\n' ~
