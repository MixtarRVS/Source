# msh-category: expansion
# msh-name: adjacent quoted literal segments still allow unquoted pathname expansion
# msh-profile: posix
: > ab
: > ac
echo "a"*
echo 'a'*
