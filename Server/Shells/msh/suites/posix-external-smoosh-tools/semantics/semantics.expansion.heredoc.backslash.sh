# msh-source: smoosh/tests/shell/semantics.expansion.heredoc.backslash.test
# msh-profile: posix
# msh-run: eval
cat <<EOF
an escaped \\[bracket]
should \\ work just fine
EOF
cat <<EOF
exit \$?
EOF