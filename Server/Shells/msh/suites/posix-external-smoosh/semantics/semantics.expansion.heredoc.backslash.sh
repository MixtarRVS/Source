# msh-source: smoosh/tests/shell/semantics.expansion.heredoc.backslash.test
# msh-profile: posix
# msh-run: eval
while IFS= read -r line
do
    printf '%s\n' "$line"
done <<EOF
an escaped \\[bracket]
should \\ work just fine
EOF
while IFS= read -r line
do
    printf '%s\n' "$line"
done <<EOF
exit \$?
EOF
