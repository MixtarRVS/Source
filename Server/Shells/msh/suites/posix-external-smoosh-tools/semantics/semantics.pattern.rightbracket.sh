# msh-source: smoosh/tests/shell/semantics.pattern.rightbracket.test
# msh-profile: posix
# msh-run: eval
touch file]
touch filea

echo file[]123]
echo file[[.].]]
echo file[[=]=]]
echo file[!]123]
echo file[[:alpha:]]
echo file[a-z]