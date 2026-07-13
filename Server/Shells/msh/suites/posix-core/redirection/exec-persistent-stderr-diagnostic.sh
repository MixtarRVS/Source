# msh-category: redirection
# msh-name: exec persistent stderr captures missing command diagnostic
exec 3>&2
exec 2>err
definitely_missing
exec 2>&3
exec 3>&-
while IFS= read -r line; do
    case $line in
        *definitely_missing*) printf found ;;
    esac
done < err
