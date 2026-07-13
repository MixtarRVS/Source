# msh-category: command-search
# msh-name: command explicit text script redirection
printf 'printf script-ok\n' > plain
command ./plain > out
status=$?
read line < out
printf 's=%s line=%s\n' "$status" "$line"
