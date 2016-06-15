/etc/stunnel/stunnel_server.conf:
  file.managed:
    - source: salt://redis_server/stunnel_server.conf
    - template: jinja
    - context:
        redis_host: {{ pillar['redis_host'] }}
        redis_domain: {{ pillar['redis_domain'] }}
    - user: root
    - group: root
    - mode: 644
    - makedirs: True
    - require:
      - pkg: stunnel4

/etc/redis/redis_auth.conf:
  file.managed:
    {% if pillar["in_production"] %}
    - source: salt://redis_server/redis_auth.conf
    {% else %}
    - source: salt://redis_server/redis_auth_test.conf
    {% endif %}
    - user: root
    - group: root
    - mode: 644
    - makedirs: True

/etc/redis/redis.conf:
  file.managed:
    - source: salt://redis_server/redis.conf
    - template: jinja
    - context:
        is_master: {{ pillar.get('is_redis_master', False) }}
    - user: root
    - group: root
    - mode: 644
    - makedirs: True

{% if pillar.get('is_redis_master', False) %}

/etc/redis/redis_master.conf:
  file.managed:
    - source: salt://redis_server/redis_master.conf
    - user: root
    - group: root
    - mode: 644
    - makedirs: True

/etc/redis/redis_slave.conf:
  file.absent

{% else %}

/etc/redis/redis_slave.conf:
  file.managed:
    - source: salt://redis_server/redis_slave.conf
    - user: root
    - group: root
    - mode: 644
    - makedirs: True

/etc/redis/redis_master.conf:
  file.absent

{% endif %}

redis-ulimit:
    file.append:
      - name: /etc/security/limits.conf
      - text: |
          redis            soft    nofile            160000
          redis            hard    nofile            160000
          root             soft    nofile            160000
          root             hard    nofile            160000

redis-server:
  pkgrepo.managed:
    - ppa: chris-lea/redis-server

  pkg.installed:
    - name: redis-server
    - refresh: True
    - version: 3:3.0.7-1chl1~trusty1
    - require:
      - pkgrepo: redis-server

disable-redis-server-sysv:
  cmd.run:
    - name: /etc/init.d/redis-server stop && update-rc.d redis-server disable

/etc/init/redis-server.conf:
  file.managed:
    - source: salt://redis_server/redis-server.conf
    - user: root
    - group: root
    - mode: 644

# Allow memory overcommit to make sure Redis background save still works even in
# low memory conditions.
vm.overcommit_memory:
  sysctl.present:
    - value: 1

# Increase somaxconn for Redis
net.core.somaxconn:
  sysctl.present:
    - value: 1024

# Disable THP for Redis's benefit. This is done permanently in rc.local
disable-THP:
  file.replace:
    - name: /sys/kernel/mm/transparent_hugepage/enabled
    - pattern: .*
    - repl: never
    - backup: False

/etc/rc.local:
  file.managed:
    - source: salt://redis_server/rc.local
    - mode: 755

redis-server-running:
  service.running:
    - name: redis-server
    - enable: yes
    - require:
        - pkg: stunnel4
        - pkg: redis-server
        - cmd: disable-redis-server-sysv
    - watch:
        - file: /etc/redis/*
        - file: /etc/init/redis-server.conf
        - file: /etc/rc.local
        - sysctl: vm.overcommit_memory
        - sysctl: net.core.somaxconn
        - cmd: stunnel4-deps

{% if not pillar["in_dev"] and pillar.get("is_redis_master", False) %}
s3cmd:
  pkg.installed

pgpgpg:
  pkg.installed

/home/lantern/.s3cfg:
  file.managed:
    - source: salt://redis_server/.s3cfg-{{ pillar['environment'] }}
    - user: lantern
    - group: lantern
    - mode: 600
    - makedirs: True

/home/lantern/s3backup.bash:
  file.managed:
    - source: salt://redis_server/s3backup.bash
    - template: jinja
    - context:
        environment: {{ pillar['environment'] }}
    - user: lantern
    - group: lantern
    - mode: 755
    - makedirs: True

/home/lantern/s3backup.bash 2>&1 | logger -t s3backup:
  cron.present:
    - identifier: s3backup
    - hour: "0,12"
    - minute: 0
    - user: lantern
    - require:
        - file: /home/lantern/.s3cfg
        - file: /home/lantern/s3backup.bash
        - pkg: s3cmd
        - pkg: pgpgpg
{% endif %}

{% set rulefiles=['user.rules', 'user6.rules'] %}
{% for file in rulefiles %}
/lib/ufw/{{ file }}:
  file.managed:
    - source: salt://redis_server/{{ file }}
    - user: root
    - group: root
    - mode: 644
    - makedirs: True
{% endfor %}

ufw reload:
  cmd.run:
    - require:
      - pkg: ufw
    - watch:
      {% for file in rulefiles %}
      - file: /lib/ufw/{{ file }}
      {% endfor %}
