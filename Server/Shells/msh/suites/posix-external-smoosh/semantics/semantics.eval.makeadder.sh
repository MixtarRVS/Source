# msh-source: smoosh/tests/shell/semantics.eval.makeadder.test
# msh-profile: posix
# msh-run: eval
makeadder() {
    eval "adder() { echo \$((\$1 + $1)) ; }"
}

makeadder 5
adder 1
makeadder 10
adder 1
