# msh-source: smoosh/tests/shell/semantics.escaping.quote.test
# msh-profile: posix
# msh-run: eval
set -e
for c in '"' '#' '%' '&' "'" '(' ')' '*' '+' ',' '-' '.' '/' ':' \
         ';' '<' '=' '>' '?' '@' '[' ']' '^' '_' '{' '|' '}' '~' ' '
do
        x=`printf '%s' "$c"`
        printf '%s\n' "$c"
        [ "$c" = "$x" ]
done
echo done
