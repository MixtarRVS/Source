unset A B C
printf '%s\n' "${A-default}"
printf '%s\n' "${B:=bee}"
printf '%s\n' "$B"
C=see
printf '%s\n' "${C:+alt}"
