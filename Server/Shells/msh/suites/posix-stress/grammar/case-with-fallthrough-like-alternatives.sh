# msh-category: grammar
# msh-name: case with fallthrough-like alternatives
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
for v in ax by cz; do
    case "$v" in
        a*|b*) printf X;;
        *) printf Z;;
    esac
done
