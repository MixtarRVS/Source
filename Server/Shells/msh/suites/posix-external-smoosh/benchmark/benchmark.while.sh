# msh-source: smoosh/tests/shell/benchmark.while.test
# msh-profile: posix
# msh-run: eval
x=0
while [ $x -lt 50 ]
do
    : $((x+=1))
done
echo $x
