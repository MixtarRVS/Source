# msh-category: process
# msh-name: trap listing pipes into read
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap '' TERM
trap | while read A B C; do
    case "$A $B $C" in
        *TERM*) printf '<seen>\n'; break;;
    esac
done
