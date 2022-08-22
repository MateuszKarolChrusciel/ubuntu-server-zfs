Original Author:  Karl Stenerud  (https://github.com/kstenerud)
===================================

Forked from https://github.com/kstenerud/ubuntu-server-zfs

Install Ubuntu server with ZFS root
-----------------------------------

This script will install Ubuntu Server with a ZFS root.

It will be a stock Ubuntu server install, except:

* The `finish-install.sh` script can be modified to install a few extra things (such as Docker, LXD, KVM, QEMU) - letfover from original script.
* When the installation completes, it will create a zfs snapshot `rpool/ROOT/ubuntu_xxxxxx@fresh-install` to save the initial state of the root filesystem.

See the [OpenZFS documentation](https://github.com/openzfs/openzfs-docs/blob/master/docs/Getting%20Started/Ubuntu/Ubuntu%2020.04%20Root%20on%20ZFS.rst) for more info.


Usage
-----

Modify the script's configuration section, then run the script from a bootstrap environment (such as the Ubuntu live CD).

To set up SSHD on the live CD so that you can do everything over SSH:

```
sudo apt install --yes openssh-server nano && echo -e "ubuntu\nubuntu" | passwd ubuntu
```

License
-------

MIT License:

Copyright 2020 Karl Stenerud

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
