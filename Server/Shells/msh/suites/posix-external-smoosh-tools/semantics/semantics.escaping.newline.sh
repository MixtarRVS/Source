# msh-source: smoosh/tests/shell/semantics.escaping.newline.test
# msh-profile: posix
# msh-run: eval
printf '%s' '\\'n
printf '%s' "\n"
printf "\n"
printf '\n'
printf '\\n'
