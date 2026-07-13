# msh-source: smoosh/tests/shell/semantics.ifs.combine.ws.test
# msh-profile: posix
# msh-run: eval
unset IFS 
echo                  > spaced
printf "%b" '\tx'    >> spaced
echo                 >> spaced
echo "          5"   >> spaced
printf '%b' ' 12\t ' >> spaced
echo `cat spaced`
IFS=$(printf '%b' ' \n\t')
echo `cat spaced`