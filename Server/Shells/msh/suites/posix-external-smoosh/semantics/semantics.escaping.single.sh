# msh-source: smoosh/tests/shell/semantics.escaping.single.test
# msh-profile: posix
# msh-run: eval
while IFS= read -r line
do
    printf '%s\n' "$line"
done <<weirdo
line one
line two
"line".\${PATH}.\'three\'\\x\
line four
weirdo
