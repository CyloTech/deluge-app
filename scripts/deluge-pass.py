#!/usr/bin/python
# Changes the password for Deluge's Web UI

from deluge.config import Config
import hashlib
import os.path
import sys
import subprocess

if len(sys.argv) == 3:
    deluge_dir = os.path.expanduser(sys.argv[1])

    if os.path.isdir(deluge_dir):
        try:
            config = Config("web.conf", config_dir=deluge_dir)
        except IOError, e:
            print "Can't open web ui config file: ", e
        else:
            p = sys.argv[2]
            password = sys.argv[2]
            s = hashlib.sha1()
            s.update(config['pwd_salt'])
            s.update(password)
            config['pwd_sha1'] = s.hexdigest()
            try:
                config.save()
            except IOError, e:
                print "Couldn't save new password: ", e
            else:
                print "New password successfully set!"
    else:
	print "%s is not a directory!" % deluge_dir
else:
    print "Usage: %s <deluge config dir> <pass>" % (os.path.basename(sys.argv[0]))