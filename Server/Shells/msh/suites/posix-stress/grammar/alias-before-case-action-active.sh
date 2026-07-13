# msh-category: grammar
# msh-name: alias before case action active
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias hi='printf ok'
case x in
    x) hi;;
esac
