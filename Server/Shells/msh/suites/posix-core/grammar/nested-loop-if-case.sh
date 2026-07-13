# msh-profile: posix
for x in a b; do
  case $x in
    a) if :; then printf 'A\n'; fi ;;
    b) while :; do printf 'B\n'; break; done ;;
  esac
done