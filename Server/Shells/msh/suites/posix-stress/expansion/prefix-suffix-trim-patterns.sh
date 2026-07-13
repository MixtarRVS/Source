# msh-category: expansion
# msh-name: prefix suffix trim patterns
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=abcabc
printf '<%s><%s><%s><%s>\n' "${A#a*}" "${A##a*}" "${A%b*}" "${A%%b*}"
