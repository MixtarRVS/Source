# msh-category: builtin
# msh-name: command eval export invalid name nonfatal
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
command eval 'export 1BAD=value'
printf after
