# msh-source: smoosh/tests/shell/semantics.expansion.quotes.adjacent.test
# msh-profile: posix
# msh-run: eval
mkdir a
touch a/b
touch a/c
echo a/*
echo "a"/*
echo 'a'/*
mkdir "foo*["
touch "foo*["/weird
touch "foo*["/wild
touch "foo*["/crazy
echo "foo*["/*
echo "foo*["/[wz]*