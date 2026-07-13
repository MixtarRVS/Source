# msh-category: expansion
# msh-name: parameter trim path suffix
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=/one/two/file.txt
printf '<%s><%s>\n' "${A%/*}" "${A##*/}"
