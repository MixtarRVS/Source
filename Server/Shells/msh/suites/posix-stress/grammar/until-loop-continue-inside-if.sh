# msh-category: grammar
# msh-name: until loop continue inside if
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
i=0
until [ "$i" -ge 3 ]; do
    i=$((i + 1))
    if [ "$i" -eq 2 ]; then
        continue
    fi
    printf "$i"
done
