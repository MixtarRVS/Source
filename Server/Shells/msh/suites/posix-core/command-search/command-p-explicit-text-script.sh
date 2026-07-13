# msh-category: command-search
# msh-name: command -p runs explicit text script
printf 'printf script-ok\n' > plain
command -p ./plain
printf 's=%s\n' $?
