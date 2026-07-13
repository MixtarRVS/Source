# msh-category: expansion
# msh-name: case pattern list expanded
p=b
case b in
    a|$p) printf yes;;
    *) printf no;;
esac
