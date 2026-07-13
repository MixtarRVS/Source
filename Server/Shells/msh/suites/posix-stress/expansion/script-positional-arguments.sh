# msh-category: expansion
# msh-name: script positional arguments
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: file
# msh-args: one 'two words'
printf '<%s><%s><%s><%s>\n' "${0##*/}" "$#" "$1" "$2"
