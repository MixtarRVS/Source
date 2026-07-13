# msh-category: grammar
# msh-name: nested if in while with break
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
i=0
while true; do
    i=$((i + 1))
    if [ "$i" -eq 2 ]; then
        printf done
        break
    fi
done
