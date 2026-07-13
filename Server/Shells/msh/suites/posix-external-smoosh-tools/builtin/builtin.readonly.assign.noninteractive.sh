# msh-source: smoosh/tests/shell/builtin.readonly.assign.noninteractive.test
# msh-profile: posix
# msh-run: eval
readonly a=b
export a=c
echo egad
