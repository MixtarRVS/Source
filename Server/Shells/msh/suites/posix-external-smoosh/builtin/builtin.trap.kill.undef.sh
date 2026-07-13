# msh-source: smoosh/tests/shell/builtin.trap.kill.undef.test
# msh-profile: posix
# msh-run: eval
trap 'echo derp' KILL
trap 'echo nevah' 9
