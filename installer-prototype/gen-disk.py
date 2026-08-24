#!/usr/bin/env python3
"""Build an archinstall config for THIS machine, disk half included.

The disk half cannot be written by hand and kept: archinstall's schema wants a
`sector_size` object inside every size, a `dev_path` key that must exist even
when it is null, and sizes that come out as absolute byte counts of the disk in
front of it. So it is not a document you author once — it is a thing you
generate, on the machine, with the same library version that will consume it.

That is also exactly what a graphical front-end of our own would do: collect the
answers, call archinstall as a library, hand the result to archinstall as JSON.
This script is the smallest possible version of that front-end.

    gen-disk.py /dev/vda nidara.json > nidara-merged.json
    gen-disk.py /dev/vda              > disk_config.json
"""

import asyncio
import json
import sys
from pathlib import Path

from archinstall.lib.disk.device_handler import device_handler
from archinstall.lib.disk.disk_menu import suggest_single_disk_layout
from archinstall.lib.models.device import (
	DiskLayoutConfiguration,
	DiskLayoutType,
	FilesystemType,
)


def main() -> None:
	if len(sys.argv) < 2:
		sys.exit(__doc__)

	dev_path = Path(sys.argv[1])
	device = device_handler.get_device(dev_path)

	# archinstall itself does NOT do this: handed a device it cannot find, it
	# skips that entry and installs onto an empty layout, exit 0. Anything built
	# on top has to refuse for it.
	if device is None:
		sys.exit(f'{dev_path}: no such block device (archinstall would have skipped it in silence)')

	# Passing both answers is what keeps this non-interactive: left to itself the
	# suggestion helper asks about the filesystem and about a separate /home.
	modification = asyncio.run(
		suggest_single_disk_layout(device, FilesystemType.EXT4, separate_home=False)
	)

	disk_config = DiskLayoutConfiguration(
		config_type=DiskLayoutType.Default,
		device_modifications=[modification],
	).json()

	if len(sys.argv) > 2:
		config = json.loads(Path(sys.argv[2]).read_text())
		config['disk_config'] = disk_config
		out = config
	else:
		out = disk_config

	print(json.dumps(out, indent=2))


if __name__ == '__main__':
	main()
