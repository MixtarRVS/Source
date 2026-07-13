# msh-category: grammar
# msh-name: linebreaks before then do and in
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
if
    true
then
    for x
    in a b
    do
        printf "$x"
    done
fi
