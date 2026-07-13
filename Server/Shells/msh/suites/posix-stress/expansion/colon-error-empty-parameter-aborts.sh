# msh-category: expansion
# msh-name: colon error empty parameter aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
A=
printf '%s\n' "${A:?empty}"
printf after
