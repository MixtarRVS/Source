V=abc
case $V in
  a*) printf 'A' ;;
  *) printf 'B' ;;
esac
printf '\n'
