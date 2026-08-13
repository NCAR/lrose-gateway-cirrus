import os
from sys import argv

lrose_stable_path = '/usr/local/lrose'
lrose_nightly_path = '/share/lrose-nightly'

def lrose_swap_path(swap_path, bin_lib):
    swap_path=swap_path.split(":")

    stable = swap_path.index(lrose_stable_path + '/' + bin_lib)
    nightly = swap_path.index(lrose_nightly_path + '/' + bin_lib)

    current = min([stable, nightly])
    new = max ([stable, nightly])

    print(f"Current LROSE {bin_lib} path: {swap_path[current]}")

    if "show" not in argv:
        print(f"Switching to: {swap_path[new]}")
        swap_path[stable], swap_path[nightly] = swap_path[nightly], swap_path[stable]
        return ':'.join(swap_path)
    else:
        return ""

lrose_tmp_path = lrose_swap_path(os.environ['PATH'], 'bin')
if lrose_tmp_path:
    os.environ['PATH'] = lrose_tmp_path

lrose_tmp_path = lrose_swap_path(os.environ['LD_LIBRARY_PATH'], 'lib')
if lrose_tmp_path:
    os.environ['LD_LIBRARY_PATH'] = lrose_tmp_path
