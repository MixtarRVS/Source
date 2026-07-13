# msh-category: grammar
# msh-name: nested compound case if loop
for x in a b; do
    case $x in
        a) if true; then printf A; fi;;
        b) while false; do printf bad; done; printf B;;
    esac
done
