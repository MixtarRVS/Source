# msh-category: builtin
# msh-name: command assignment return temporary
f() {
    A=inner command return 3
}
A=outer
f
status=$?
printf '<%s:%s>\n' "$A" "$status"
