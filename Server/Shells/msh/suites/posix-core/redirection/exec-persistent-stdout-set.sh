# msh-category: redirection
# msh-name: exec persistent stdout captures set output
exec 3>&1
MSH_FD_SET=ok
exec >out
set
exec >&3
exec 3>&-
while IFS= read -r line; do
    case $line in
        *MSH_FD_SET*) printf '%s' "$line" ;;
    esac
done < out
