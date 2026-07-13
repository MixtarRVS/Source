{
  printf '%s\n' 'printf before'
  printf '%s\n' 'return 9'
  printf '%s\n' 'printf after'
} > s.sh
. ./s.sh
printf 'status=%s\n' "$?"
