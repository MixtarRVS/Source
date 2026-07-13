# msh-profile: posix
p=$(printf 'a*')
case abc in
  $p) printf 'match\n' ;;
  *) printf 'miss\n' ;;
esac