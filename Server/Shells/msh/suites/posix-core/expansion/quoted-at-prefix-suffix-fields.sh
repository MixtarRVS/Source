# msh-profile: posix
set -- 'a b' c
for x in x"$@"y; do
  printf '<%s>\n' "$x"
done