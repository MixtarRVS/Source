# msh-category: builtin
# msh-name: command eval redirection failure is nonfatal
# msh-stderr: normalized
command eval : > ./missing_dir/out
printf 'after:%s\n' $?
