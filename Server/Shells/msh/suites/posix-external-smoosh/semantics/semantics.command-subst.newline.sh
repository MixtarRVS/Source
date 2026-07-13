# msh-source: smoosh/tests/shell/semantics.command-subst.newline.test
# msh-profile: posix
# msh-run: eval
while IFS= read -r line
do
    printf '%s\n' "$line"
done <<END
1
$(echo "")
2
END
