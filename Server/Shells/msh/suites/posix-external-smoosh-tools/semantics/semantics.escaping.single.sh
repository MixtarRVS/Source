# msh-source: smoosh/tests/shell/semantics.escaping.single.test
# msh-profile: posix
# msh-run: eval
# cf tp399
cat <<weirdo
line one
line two
"line".\${PATH}.\'three\'\\x\
line four
weirdo
