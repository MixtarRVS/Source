# msh-category: grammar
# msh-name: case leading paren multiple patterns
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
case b in
    (a|b) printf match;;
    (*) printf miss;;
esac
