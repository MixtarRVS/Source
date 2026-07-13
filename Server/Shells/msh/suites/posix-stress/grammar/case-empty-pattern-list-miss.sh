# msh-category: grammar
# msh-name: case empty pattern list miss
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
case x in
    '') printf empty;;
    x) printf x;;
esac
