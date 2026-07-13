# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
OUT=$(MSH_TEMP_ASSIGN=child "$TEST_SHELL" -c 'printf "%s" "$MSH_TEMP_ASSIGN"')
printf '[%s][%s]\n' "$OUT" "${MSH_TEMP_ASSIGN-unset}"
