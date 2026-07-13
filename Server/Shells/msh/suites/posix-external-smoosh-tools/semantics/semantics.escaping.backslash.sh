# msh-source: smoosh/tests/shell/semantics.escaping.backslash.test
# msh-profile: posix
# msh-run: eval
printf '%s\t\n'  > scr \
       'printf %s\\n foobar\|\&\;\<\>\(\)\$\`\\\"\'\''\ \?\*\[\'
$TEST_SHELL scr

