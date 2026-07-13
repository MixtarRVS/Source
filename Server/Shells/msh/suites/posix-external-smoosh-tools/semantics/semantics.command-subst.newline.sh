# msh-source: smoosh/tests/shell/semantics.command-subst.newline.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01844.html
cat <<END
1
$(echo "")
2
END