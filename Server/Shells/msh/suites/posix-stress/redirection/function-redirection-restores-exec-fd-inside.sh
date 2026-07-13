# msh-category: redirection
# msh-name: function redirection restores exec fd inside
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
f() { exec 8>inner; printf I >&8; }
f 8>temp
printf O >&8
exec 8>&-
read A < inner
read B < temp
printf '<%s:%s>\n' "$A" "$B"
