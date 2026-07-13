# msh-category: process
# msh-name: type output pipes into read
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
type printf | while read A B C; do
    case "$A $B $C" in
        *printf*) printf '<seen>\n'; break;;
    esac
done
