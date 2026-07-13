# msh-name: assignment before return persists after function return
# msh-profile: posix
f() {
    A=one return 3
    A=bad
}
f
printf '<%s/%s>\n' "$A" "$?"
