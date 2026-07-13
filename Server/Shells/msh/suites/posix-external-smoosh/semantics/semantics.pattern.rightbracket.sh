# msh-source: smoosh/tests/shell/semantics.pattern.rightbracket.test
# msh-profile: posix
# msh-run: eval
: >file]
: >filea
echo file[]123]
echo file[[.].]]
echo file[[=]=]]
echo file[!]123]
echo file[[:alpha:]]
echo file[a-z]
