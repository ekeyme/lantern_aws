{% set fallback_json_file='/home/lantern/fallback.json' %}
{% set proxy_protocol=pillar.get('proxy_protocol', 'tcp') %}
{% set auth_token=pillar.get('auth_token') %}
{% set proxy_port=pillar.get('proxy_port', 443) %}
{% set obfs4_port=pillar.get('obfs4_port', 0) %}
{% set traffic_check_period_minutes=60 %}
{% from 'ip.sls' import external_ip %}

fp-dirs:
  file.directory:
    - names:
        - /var/log/http-proxy
    - user: lantern
    - group: lantern
    - mode: 755
    - makedirs: yes
    - recurse:
        - user
        - group
        - mode

# To filter through jinja.
{% set template_files=[
    ('/etc/init/', 'http-proxy.conf', 'http-proxy.conf', 'root', 644),
    ('/home/lantern/', 'util.py', 'util.py', 'lantern', 400),
    ('/home/lantern/', 'check_load.py', 'check_load.py', 'lantern', 700),
    ('/home/lantern/', 'check_vultr_transfer.py', 'check_vultr_transfer.py', 'lantern', 700),
    ('/home/lantern/', 'auth_token.txt', 'auth_token.txt', 'lantern', 400),
    ('/home/lantern/', 'config.ini', 'config.ini', 'lantern', 400),
    ('/home/lantern/', 'fallback.json', 'fallback.json', 'lantern', 400)] %}

# To copy verbatim.
{% set nontemplate_files=[
    ('/home/lantern/', 'http-proxy', 'http-proxy', 'lantern', 755),
    ('/usr/local/bin/', 'badvpn-udpgw', 'badvpn-udpgw', 'root', 755),
    ('/etc/init.d/', 'badvpn-udpgw', 'udpgw-init', 'root', 755),
    ('/etc/', 'rc.local', 'rc.local', 'root', '755')] %}

include:
    - proxy_ufw_rules
    - redis
{% if pillar['datacenter'].startswith('vl') %}
    - vultr
{% endif %}

{% for dir,dst_filename,src_filename,user,mode in template_files %}
{{ dir+dst_filename }}:
    file.managed:
        - source: salt://http_proxy/{{ src_filename }}
        - template: jinja
        - context:
            auth_token: {{ auth_token }}
            external_ip: {{ external_ip(grains) }}
            proxy_port: {{ proxy_port }}
            obfs4_port: {{ obfs4_port }}
            traffic_check_period_minutes: {{ traffic_check_period_minutes }}
        - user: {{ user }}
        - group: {{ user }}
        - mode: {{ mode }}
        - require:
            - file: fp-dirs
{% endfor %}

{% for dir,dst_filename,src_filename,user,mode in nontemplate_files %}
{{ dir+dst_filename }}:
    file.managed:
        - source: salt://http_proxy/{{ src_filename }}
        - user: {{ user }}
        - group: {{ user }}
        - mode: {{ mode }}
        - require:
            - file: fp-dirs
{% endfor %}

allow-bind-low-port:
  cmd.run:
    - name: setcap 'cap_net_bind_service=+ep' /home/lantern/http-proxy
    - watch:
      - file: /home/lantern/http-proxy

fallback-proxy-dirs-and-files:
    cmd.run:
        - name: ":"
        - require:
            {% for dir,dst_filename,src_filename,user,mode in template_files %}
            - file: {{ dir+dst_filename }}
            {% endfor %}
            {% for dir,dst_filename,src_filename,user,mode in nontemplate_files %}
            - file: {{ dir+dst_filename }}
            {% endfor %}

save-access-data:
    cmd.script:
        - source: salt://http_proxy/save_access_data.py
        - template: jinja
        - context:
            fallback_json_file: {{ fallback_json_file }}
            obfs4_port: {{ obfs4_port }}
        - user: lantern
        - group: lantern
        - cwd: /home/lantern
        - order: last
        - require:
            - file: {{ fallback_json_file }}
            - cmd: convert-cert
            - service: proxy-service

zip:
    pkg.installed

/home/lantern/report_stats.py:
    cron.absent:
        - user: lantern


{% if pillar['in_production'] or pillar['in_staging'] %}


uptime:
    pip.installed

"/home/lantern/check_load.py 2>&1 | logger -t check_load":
  cron.present:
    - minute: "*"
    - user: lantern
    - require:
        - file: /home/lantern/check_load.py
        - pip: uptime
        - pkg: python-redis

"/home/lantern/check_traffic.py 2>&1 | logger -t check_traffic":
  cron.absent:
    - user: lantern

{% if pillar['datacenter'].startswith('vl') %}

{% set offset=[0, 1, 2]|random %}
"/home/lantern/check_vultr_transfer.py 2>&1 | logger -t check_vultr_transfer":
  cron.present:
    - identifier: check_vultr_transfer
    - minute: random
            {# There is probably some Jinja shortcut for this, but this works. #}
    - hour: {{ [0 + offset, 3 + offset, 6 + offset, 9 + offset, 12 + offset, 15 + offset, 18 + offset, 21 + offset]|join(',') }}
    - user: lantern
    - require:
        - file: /home/lantern/check_vultr_transfer.py
        - pip: vultr
        - pkg: python-redis

{% endif %}

{% endif %}

# Dictionary of American English words for the dname generator in
# generate-cert.
wamerican:
    pkg.installed

tcl:
    pkg.installed

generate-cert:
    cmd.script:
        - source: salt://http_proxy/gencert.py
        - template: jinja
        # Don't clobber the keystore of old fallbacks.
        - creates: /home/lantern/littleproxy_keystore.jks
        - require:
            - pkg: wamerican

convert-cert:
    cmd.script:
        - source: salt://http_proxy/convcert.sh
        - user: lantern
        - group: lantern
        - mode: 400
        - require:
            - cmd: generate-cert

proxy-service:
    service.running:
        - name: http-proxy
        - enable: yes
        - watch:
            - cmd: fallback-proxy-dirs-and-files
            - cmd: convert-cert
            - file: /home/lantern/http-proxy
            - file: /home/lantern/config.ini
        - require:
            - pkg: tcl
            - cmd: ufw-rules-ready
            - service: ats-disabled
            - service: lantern-disabled
            - service: badvpn-udpgw

badvpn-udpgw:
  service.running:
    - enable: yes
    - watch:
        - cmd: fallback-proxy-dirs-and-files

# Remove cron job that tries to make sure lantern-java is working, in old
# servers.
/home/lantern/check_lantern.py:
    cron.absent:
        - user: root

ats-disabled:
    service.dead:
        - name: trafficserver
        - enable: no

# Disable Lantern-java in old servers.
lantern-disabled:
    service.dead:
        - name: lantern
        - enable: no
        - require:
            - cron: /home/lantern/check_lantern.py


# Not strictly necessary perhaps, but make sure, for good measure, that old
# lantern init scripts are not around.

/etc/init.d/lantern:
    file.absent:
        - require:
            - service: lantern-disabled

/etc/init.d/http-proxy:
    file.absent:
        - require:
            - file: /etc/init/http-proxy.conf

/etc/init.d/trafficserver:
    file.absent:
        - require:
            - service: ats-disabled

# Increase syn_backlog to avoid dropping of opened connections
net.ipv4.tcp_max_syn_backlog:
    sysctl.present:
        - value: 4096

# Increase the current txqueuelen
# This is done permanently in /etc/rc.local
/sbin/ifconfig eth0 txqueuelen 20000:
    cmd.run
