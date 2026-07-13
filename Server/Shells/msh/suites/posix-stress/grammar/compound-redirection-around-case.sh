# msh-category: grammar
# msh-name: compound redirection around case
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
case x in
    x) printf A;;
esac > out
read X < out
printf '<%s>\n' "$X"
