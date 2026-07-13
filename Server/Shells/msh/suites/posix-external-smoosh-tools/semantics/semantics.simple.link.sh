# msh-source: smoosh/tests/shell/semantics.simple.link.test
# msh-profile: posix
# msh-run: file
set -e
echo 'echo hi' >cmd.sh
chmod +x cmd.sh
ln -s cmd.sh link.sh
OLDPATH=$PATH
PATH=.
[ -x cmd.sh ]
[ -L link.sh ]
cmd.sh  # command works
link.sh # symlink works
PATH=$OLDPATH
ls
rm cmd.sh link.sh