project(
  'mixtar-mwm',
  'c',
  version: '0.1.0',
  default_options: [
    'buildtype=release',
    'c_std=gnu11',
    'warning_level=3',
  ],
)

add_project_arguments(
  '-DWLR_USE_UNSTABLE',
  '-ffunction-sections',
  '-fdata-sections',
  language: 'c',
)

wlroots = dependency('wlroots-0.20', version: '>=0.20.2')
wayland_server = dependency('wayland-server', version: '>=1.24.0')
xkbcommon = dependency('xkbcommon', version: '>=1.8.0')

executable(
  'MWM',
  'mwm.c',
  dependencies: [wlroots, wayland_server, xkbcommon],
  install: true,
  install_dir: join_paths(get_option('prefix'), 'Core', 'Graphics'),
  install_rpath: '/System/Libraries/Graphics:/System/Libraries',
  link_args: [
    '-Wl,--as-needed',
    '-Wl,--gc-sections',
    '-Wl,-z,relro',
    '-Wl,-z,now',
    '-Wl,--dynamic-linker=/System/Libraries/Loader/ld-linux-x86-64.so.2',
  ],
)
