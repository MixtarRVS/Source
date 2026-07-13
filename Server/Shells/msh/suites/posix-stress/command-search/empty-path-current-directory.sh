# msh-category: command-search
# msh-name: empty path current directory
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'printf local\n' > localcmd
chmod +x localcmd 2>/dev/null || :
PATH=:
localcmd
