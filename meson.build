project('itch-replay', 'c', 'cpp',
  version : '0.1',
  default_options : ['c_std=gnu17', 'cpp_std=c++20', 'buildtype=debugoptimized', 'warning_level=2'])

dpdk = dependency('libdpdk')

executable('itch-replay', 'src/main.c',
  dependencies : dpdk,
  c_args : ['-march=native'])
