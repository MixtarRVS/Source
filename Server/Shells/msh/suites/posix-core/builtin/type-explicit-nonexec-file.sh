printf '%s\n' 'printf nope' > probe-file
chmod 644 probe-file
type ./probe-file
