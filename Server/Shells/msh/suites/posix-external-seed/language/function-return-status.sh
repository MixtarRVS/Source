f() { printf 'before\n'; return 7; printf 'after\n'; }
f
printf 'status=%s\n' "$?"
