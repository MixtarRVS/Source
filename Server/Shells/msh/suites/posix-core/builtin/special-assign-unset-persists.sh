# msh-name: assignment before unset persists while unset mutates target
# msh-profile: posix
B=two
A=one unset B
printf '<%s/%s>\n' "$A" "${B:-missing}"
