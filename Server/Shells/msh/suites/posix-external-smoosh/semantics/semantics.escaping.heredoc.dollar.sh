# msh-source: smoosh/tests/shell/semantics.escaping.heredoc.dollar.test
# msh-profile: posix
# msh-run: eval
while IFS= read -r line
do
    printf '%s\n' "$line"
done <<EOF
echo \\\$var
EOF
while IFS= read -r line
do
    printf '%s\n' "$line"
done <<'EOF'
echo \\\$var
EOF
