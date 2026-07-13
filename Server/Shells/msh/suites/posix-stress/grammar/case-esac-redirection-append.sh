# msh-category: grammar
# msh-name: case esac redirection append
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf old > out
case x in
    x) printf new;;
esac >> out
read X < out
printf '<%s>\n' "$X"
