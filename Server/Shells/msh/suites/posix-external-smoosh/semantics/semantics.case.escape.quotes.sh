# msh-source: smoosh/tests/shell/semantics.case.escape.quotes.test
# msh-profile: posix
# msh-run: eval
foo=\"
echo -n Literal: ''
case "$foo" in
    \" ) echo OK ;;
    * ) echo NOT OK ;;
esac
echo -n Unquoted: ''
case "$foo" in
    $foo ) echo OK ;;
    * ) echo NOT OK ;;
esac
echo -n Quoted: ''
case "$foo" in
    "$foo" ) echo OK ;;
    * ) echo NOT OK ;;
esac
