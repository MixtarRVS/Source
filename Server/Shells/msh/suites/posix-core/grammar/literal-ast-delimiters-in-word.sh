# msh-name: literal AST delimiters survive word serialization
# msh-profile: posix
printf '%s\n' 'WORD("x"),REDIR(">","]")'
