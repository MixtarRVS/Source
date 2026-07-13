# msh-source: smoosh/tests/shell/semantics.redir.toomany.test
# msh-profile: posix
# msh-run: eval
c="echo hi"
n=3
while [ "$n" -le 10 ]
do
        c="{ $c; echo hi; } >file_$n"
        n=$((n + 1))
done
eval "$c" 2>err
[ -e err ] && ! [ -s err ] || exit 2
