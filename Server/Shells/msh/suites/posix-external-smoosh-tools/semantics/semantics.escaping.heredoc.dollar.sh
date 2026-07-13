# msh-source: smoosh/tests/shell/semantics.escaping.heredoc.dollar.test
# msh-profile: posix
# msh-run: eval
cat <<EOF
echo \\\$var
EOF
cat <<'EOF'
echo \\\$var
EOF
