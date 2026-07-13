# msh-source: smoosh/tests/shell/semantics.command.argv0.test
# msh-profile: posix
# msh-run: eval
set -e

explicit=$(${TEST_UTIL}/argv)
[ "$explicit" = "argv[0] = \"${TEST_UTIL}/argv\";" ]

PATH="${TEST_UTIL}:$PATH"
inpath=$(argv)
[ "$inpath" = "argv[0] = \"argv\";" ]
argv

