# msh-category: process
# msh-name: kill list pipes into read
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
kill -l | while read A B C; do
    case "$A$B$C" in
        ?*) printf '<seen>\n'; break;;
    esac
done
