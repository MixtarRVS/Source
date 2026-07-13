# msh-source: smoosh/tests/shell/builtin.export.unset.test
# msh-profile: posix
# msh-run: eval
set -e
unset x
export x
case "$(export -p)" in
  *"export x"*) echo ok ;;
  *) exit 1 ;;
esac
