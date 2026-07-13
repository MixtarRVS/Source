# msh-category: grammar
# msh-name: nested function group subshell
f() { { (printf inner); }; }
f
