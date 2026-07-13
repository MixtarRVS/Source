# msh-category: expansion
# msh-name: case pattern expanded
p=a
case a in
    $p) printf yes;;
    *) printf no;;
esac
