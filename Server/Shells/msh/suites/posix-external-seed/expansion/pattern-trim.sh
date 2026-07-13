P=/a/b/c.txt
printf '%s\n' "${P##*/}"
printf '%s\n' "${P%.*}"
