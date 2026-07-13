# msh-category: grammar
# msh-name: alias inside case action not active same compound
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
case x in
    x) alias hi='printf ok'; hi;;
esac
