# msh-profile: posix
exec 3>&1
exec > out
if true; then
    printf 'if\n'
fi
i=1
while [ "$i" = 1 ]; do
    printf 'while\n'
    i=0
done
for x in for; do
    printf '%s\n' "$x"
done
case x in
    x) printf 'case\n' ;;
esac
exec >&3
exec 3>&-
exec < out
read a
read b
read c
read d
printf '%s:%s:%s:%s\n' "$a" "$b" "$c" "$d"
