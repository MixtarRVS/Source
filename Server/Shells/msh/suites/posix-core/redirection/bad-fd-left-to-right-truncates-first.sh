# msh-category: redirection
# msh-name: bad fd preserves left-to-right truncation
# msh-stderr: normalized
printf old > out
command : > out 3>&9
printf 'status:%s ' "$?"
if [ -s out ]; then
    printf nonempty
else
    printf empty
fi
