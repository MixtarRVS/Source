# msh-category: pipeline
# msh-name: times to group read
times | {
    read A
    case "$A" in
        *m*s\ *m*s) printf 'ok\n' ;;
        *) printf 'bad:%s\n' "$A" ;;
    esac
}
