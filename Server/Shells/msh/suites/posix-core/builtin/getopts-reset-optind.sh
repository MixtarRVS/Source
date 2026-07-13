# msh-profile: posix
set -- -a -b
getopts 'ab' one
printf 'one:%s:%s\n' "$one" "$OPTIND"
OPTIND=1
getopts 'ab' two
printf 'two:%s:%s\n' "$two" "$OPTIND"