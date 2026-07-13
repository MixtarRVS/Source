# msh-category: redirection
# msh-name: exec persistent stdout captures readonly output
exec 3>&1
readonly MSH_FD_READONLY=ok
exec >out
readonly -p
exec >&3
exec 3>&-
while IFS= read -r line; do
    case $line in
        *MSH_FD_READONLY*) printf '%s' "$line" ;;
    esac
done < out
