# msh-category: process
# msh-name: command verbose pipes into read
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
command -V printf | while read A B C; do
    case "$A $B $C" in
        *printf*) printf '<seen>\n'; break;;
    esac
done
