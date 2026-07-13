trap 'printf "trap:%s:%s\n" "$?" "$A"' EXIT
A=ok
exit 3
