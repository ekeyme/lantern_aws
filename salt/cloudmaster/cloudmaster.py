#!/usr/bin/env python

from base64 import b64encode
from contextlib import contextmanager
from datetime import datetime
from cPickle import dumps
import json
import logging
import os
from random import SystemRandom
import string
import sys
import time
from functools import wraps

from lockfile import LockFile
import boto.sqs
from boto.sqs.jsonmessage import JSONMessage
import yaml


random = SystemRandom()
here = os.path.dirname(sys.argv[0]) if __name__ == '__main__' else __file__


PRIVATE_IP = "{{ grains['ec2_local-ipv4'] }}"
PUBLIC_IP = "{{ grains['ec2_public-ipv4'] }}"
#DRY warning: ../top.sls
FALLBACK_PROXY_PREFIX = "fp-"
MAP_FILE = '/home/lantern/map'
WB_MAP_FILE = '/home/lantern/wb_map'
AWS_REGION = "{{ grains['aws_region'] }}"
AWS_ID = "{{ pillar['aws_id'] }}"
AWS_KEY = "{{ pillar['aws_key'] }}"
CONTROLLER = "{{ grains['controller'] }}"
PRODUCTION_CONTROLLER = "{{ grains['production_controller'] }}"
SALT_VERSION = "{{ pillar['salt_version'] }}"
aws_creds = {'aws_access_key_id': AWS_ID,
             'aws_secret_access_key': AWS_KEY}
PROVIDERS = ['aws', 'do']
REDIRECT = " >> /home/lantern/cloudmaster.log 2>&1 "
SALT_PATH = '/usr/local/bin/salt'
SALT_CLOUD_PATH = '/usr/local/bin/salt-cloud'

# Most cloud providers will allow longer instance names, but we are using
# this as the hostname in those machines too.  Hostnames longer than this
# may be problematic if we want to make FQDN names out of them.
MAX_INSTANCE_NAME_LENGTH = 64

AUTH_TOKEN_ALPHABET = string.letters + string.digits
AUTH_TOKEN_LENGTH = 64


def get_provider():
    return 'do'

def get_master_ip(provider):
    return {'aws': PRIVATE_IP, 'do': PUBLIC_IP}[provider]

def log_exceptions(f):
    @wraps(f)
    def deco(*args, **kw):
        try:
            return f(*args, **kw)
        except Exception as e:
            log.exception(e)
            raise
    return deco

def check_q():
    now = time.time()
    with LockFile(MAP_FILE):
        if time.time() - now > 60:
            log.info("Took too long to acquire lock; letting go...")
            return
        try:
            actually_check_q()
        except:
            pass

@log_exceptions
def actually_check_q():
    log.info("Checking queue...")
    sqs = boto.sqs.connect_to_region(AWS_REGION, **aws_creds)
    ctrl_req_q = sqs.get_queue("%s_request" % CONTROLLER)
    ctrl_req_q.set_message_class(JSONMessage)
    msg = ctrl_req_q.read()
    if msg is None:
        log.info("Nothing in request queue.")
        return
    d = msg.get_body()
    # DRY warning: FallbackProxyLauncher at lantern-controller.
    # TRANSITION: support old controllers for a while to make deployment less
    # time sensitive.
    userid = d.get('launch-fp-as', d.get('launch-invsrv-as'))
    if userid:
        # Lantern won't start without *some* refresh token.  If we don't get one
        # from the controller let's just make up a bogus one.
        refresh_token = d.get('launch-refrtok', '').strip() or 'bogus'
        # Backwards compatibility: we'll be getting serial numbers starting
        # from 1 in the new fallback balancing scheme.  Just in case we get
        # a new proxy launch request from an old controller, let's mark it as
        # 0.
        serial = d.get('launch-serial', 0)
        # Salt scripts consuming these should use backwards-compatible defaults.
        pillars = d.get('launch-pillars', {})
        # Default proxy_protocol to tcp
        pillars.setdefault('proxy_protocol', 'tcp')
        # Make new fallbacks install from git by default.  We can't do this in
        # the fallback Salt config because there the defaults need to be
        # backwards compatible with old-style fallbacks.  We can't upgrade
        # those until we EOL old clients, since the new style of fallback
        # requires an auth token, that old fallbacks don't know to provide.
        pillars.setdefault('install-from', 'git')
        if 'auth_token' not in pillars:
            pillars['auth_token'] = random_auth_token()
        launch_proxy(userid,
                     serial,
                     refresh_token,
                     msg,
                     pillars)
    elif 'shutdown-fp' in d:
        instance_id = d['shutdown-fp']
        log.info("Got shutdown request for %s" % instance_id)
        nproxies = shutdown_instance(instance_id)
        if nproxies != 1:
            log.error("Expected one proxy shut down, got %s" % nproxies)
        ctrl_req_q.delete_message(msg)
    elif 'upload-wrappers-to' in d:
        upload_wrappers(msg)
    elif 'launch-wb' in d:
        log.info("Got launch request for wrapper builder")
        wbid = d['launch-wb']
        if not wbid.startswith("wb-"):
            log.error("Expected id starting with 'wb-'")
        else:
            launch_wrapper_builder(wbid)
        ctrl_req_q.delete_message(msg)
    else:
        log.error("I don't understand this message: %s" % d)

def launch_proxy(email, serialno, refresh_token, msg, pillars):
    log.info("Got spawn request for '%s'" % clip_email(email))
    instance_name = create_instance_name(email, serialno)
    provider = get_provider()
    if shutdown_instance(name_prefix(email, serialno)):
        # The Digital Ocean salt-cloud implementation will still find the
        # old instance if we try and recreate it too soon after deleting
        # it.
        log.info("Waiting for the instance loss to sink in...")
        time.sleep(20)
    with proxy_map() as d:
        proxy_port = 62443 if pillars['proxy_protocol'] == 'tcp' \
                              else random.randint(1024, 61024)
        d[provider].append(
            {instance_name:
                {'minion': {'master': get_master_ip(provider)},
                 'grains': {'saltversion': SALT_VERSION,
                            'aws_region': AWS_REGION,
                            'controller': CONTROLLER,
                            'production_controller': PRODUCTION_CONTROLLER,
                            'proxy_port': proxy_port,
                            'provider': provider,
                            'shell': '/bin/bash'}}})
    set_pillar(instance_name, email, refresh_token, msg, pillars)
    os.system("%s -y -m %s %s" % (SALT_CLOUD_PATH, MAP_FILE, REDIRECT))
    os.system("%s %s state.highstate %s" % (SALT_PATH, instance_name, REDIRECT))

def launch_wrapper_builder(wbid):
    if shutdown_instance(wbid):
        # The Digital Ocean salt-cloud implementation will still find the
        # old instance if we try and recreate it too soon after deleting
        # it.
        log.info("Waiting for the instance loss to sink in...")
        time.sleep(20)
    
    # Only launch on Digital Ocean
    provider = "do"
    
    with wb_map() as d:
        d[provider].append(
            {wbid:
                {'minion': {'master': get_master_ip(provider)},
                 'grains': {'saltversion': SALT_VERSION,
                            'aws_region': AWS_REGION,
                            'controller': CONTROLLER,
                            'production_controller': PRODUCTION_CONTROLLER,
                            'provider': provider,
                            'shell': '/bin/bash'}}})
    
    os.system("%s -y -m %s %s" % (SALT_CLOUD_PATH, WB_MAP_FILE, REDIRECT))
    os.system("%s %s state.highstate %s" % (SALT_PATH, wbid, REDIRECT))
    
def shutdown_instance(prefix):
    count = 0
    with proxy_map() as d:
        for provider in PROVIDERS:
            for entry in d[provider][:]:
                entry_name, = entry.keys()
                if entry_name.startswith(prefix):
                    log.info("Found match in map.  Shutting it down...")
                    d[provider].remove(entry)
                    os.system("%s -y -d %s %s" % (SALT_CLOUD_PATH, entry_name, REDIRECT))
                    count += 1
    return count

def upload_wrappers(sqs_msg):
    log.info("Uploading wrappers.")
    from salt.client import LocalClient
    load, builder = min((float(v), k)
                         for k, v in LocalClient().cmd(
                                 'wb-*',
                                 'cmd.run',
                                 ("/home/lantern/percent_mem.py",))
                            .iteritems())
    log.info("upload_wrappers: chose %r" % builder)
    log.info("memory usage: %s%%" % load)
    encoded_msg = b64encode(dumps(sqs_msg))
    # For debugging.
    file("/home/lantern/last_wrapper_msg", 'w').write(encoded_msg)
    jobid = LocalClient().cmd_async(builder,
                                    'cmd.run',
                                    ['/home/lantern/upload_wrappers.py ' + encoded_msg])
    if jobid == 0:
        log.error("upload_wrappers returned 0.")
    else:
        log.info("jobid: %r" % jobid)
 
def set_pillar(instance_name, email, refresh_token, msg, extra_pillars):
    filename = '/home/lantern/%s.sls' % instance_name
    yaml.dump(dict(instance_id=instance_name,
                   # DRY warning:
                   # lantern_aws/salt/fallback_proxy/report_completion.py
                   user=email,
                   refresh_token=refresh_token,
                   sqs_msg=b64encode(dumps(msg)),
                   **extra_pillars),
              file(filename, 'w'))
    os.system("mv %s /srv/pillar/" % filename)

@contextmanager
def proxy_map():
    d = load_map(MAP_FILE)
    yield d
    save_map(MAP_FILE, d)
    
@contextmanager
def wb_map():
    d = load_map(WB_MAP_FILE)
    yield d
    save_map(WB_MAP_FILE, d)

def load_map(filename):
    if os.path.exists(filename):
        return yaml.load(file(filename))
    else:
        return dict((p, []) for p in PROVIDERS)

def save_map(filename, d):
    yaml.dump(d, file(filename, 'w'))

def create_instance_name(email, serialno):
    now = datetime.now()
    return "%s%s-%s-%s" % (name_prefix(email, serialno),
                           now.year, now.month, now.day)

def find_instance_names(iterable, email, serialno):
    return [name for name in iterable
            if name.startswith(name_prefix(email, serialno))]

def name_prefix(email, serialno):
    sanitized_email = email.replace('@', '-at-').replace('.', '-dot-')
    # Since '-' is legal in e-mail usernames and domain names, and although
    # I don't imagine we'd approve problematic e-mails, let's be somewhat
    # paranoid and add some hash of the unsanitized e-mail to avoid clashes.
    sanitized_email += "-" + hex(hash(email))[-4:]
    # e-mail addresses can be up to 254 characters long!
    max_email_length = MAX_INSTANCE_NAME_LENGTH - len("-##-YYYY-MM-DD")
    if len(sanitized_email) > max_email_length:
        sanitized_email = "%x" % hash(email)
    return "fp-%s-%s-" % (sanitized_email, serialno)

def clip_email(email):
    at_index = email.find('@')
    return '%s...%s' % (email[:1], email[at_index-2:at_index])

def random_auth_token():
    return ''.join(random.choice(AUTH_TOKEN_ALPHABET)
                   for _ in xrange(AUTH_TOKEN_LENGTH))

if __name__ == '__main__':
    # I have to do all this crap because salt hijacks the root logger.
    log = logging.getLogger('cloudmaster')
    log.setLevel(logging.INFO)
    handler = logging.FileHandler(os.path.join(here, "cloudmaster.log"))
    handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)-8s %(message)s'))
    log.addHandler(handler)
    log.info("cloudmaster starting...")
    check_q()
    log.info("cloudmaster done.")
