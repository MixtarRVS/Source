# msh-category: process
# msh-name: export listing pipes into read
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
export PIPE_A=ok
export -p | while read A B C; do
    case "$A $B $C" in
        *PIPE_A*) printf '<seen>\n'; break;;
    esac
done
