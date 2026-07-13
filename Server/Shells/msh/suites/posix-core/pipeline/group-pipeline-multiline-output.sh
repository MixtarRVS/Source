# msh-profile: posix
{ printf 'a\n'; printf 'b\n'; } | while read x; do printf '<%s>\n' "$x"; done