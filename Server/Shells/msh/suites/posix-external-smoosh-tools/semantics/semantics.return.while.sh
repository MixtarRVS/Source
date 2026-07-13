# msh-source: smoosh/tests/shell/semantics.return.while.test
# msh-profile: posix
# msh-run: eval
f() {
    while return 5
    do  
        echo fail while
        break
    done    
}
f
echo $?

g() {
    while ! return 6
    do  
        echo fail while
        break
    done    
}
g
echo $?