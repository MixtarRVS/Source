# msh-category: pipeline
# msh-name: readonly p to group read
readonly MSH_PIPE_READONLY=needle
readonly -p | { read A; printf '<%s>\n' "$A"; }
