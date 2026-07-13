# msh-category: pipeline
# msh-name: tail missing command status
true | definitely_missing_command
printf $?
