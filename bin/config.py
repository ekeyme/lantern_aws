import os
import os.path
import sys

import here

# Values for production deployment.
salt_version = 'v2015.5.5'
production_cloudmasters = ['cm-doams3', 'cm-vltok1']
datacenter = os.getenv("DC", 'doams3')
cloudmaster_name = 'cm-' + datacenter
cloudmaster_address = {'doams3':  '188.166.35.238',
                       'vltok1': '45.32.14.144'}[datacenter]

# To override values locally, put them in config_overrides.py (not version controlled)
try:
    # Import local config overrides if available
    from config_overrides import *
except ImportError:
    print >> sys.stderr, "Import error, please check bin/config_overrides.py"
    pass


# Derived, but may still want to override?
key_path = os.path.join(here.secrets_path,
                        'lantern_aws',
                        'cloudmaster.id_rsa')

print >> sys.stderr, "Using cloudmaster: %s(%s)" % (cloudmaster_name, cloudmaster_address)
