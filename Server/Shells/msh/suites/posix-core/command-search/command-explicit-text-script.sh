# msh-category: command-search
# msh-name: command runs explicit text script
printf 'printf script-ok\n' > plain
command ./plain
printf 's=%s\n' $?
