include:
  - redis

cfgsrv-env-authtoken:
  file.replace:
    - name: /etc/environment
    - append_if_not_found: True
    - pattern: "^AUTH_TOKEN=.+$"
    - repl: AUTH_TOKEN='{{ pillar['cfgsrv_token'] }}'

cfgsrv-env-rediscloud:
  file.replace:
    - name: /etc/environment
    - append_if_not_found: True
    - pattern: "^REDISCLOUD_URL=.+$"
    - repl: REDISCLOUD_URL='{{ pillar['redis_via_stunnel_url'] }}'

cfgsrv-env-production:
  file.replace:
    - name: /etc/environment
    - append_if_not_found: True
    - pattern: "^PRODUCTION=.+$"
    # Note - the below flag doesn't do much, and it's okay to have it set to
    # true even in non-production environments.
    - repl: PRODUCTION=true

cfgsrv-env-port:
  file.replace:
    - name: /etc/environment
    - append_if_not_found: True
    - pattern: "^PORT=.+$"
    - repl: PORT=62000

/etc/stunnel/stunnel_client.conf:
  file.managed:
    - source: salt://config_server/stunnel_client.conf
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

/home/lantern/config-server.jar:
  file.managed:
    - source: salt://config_server/config-server.jar
    - mode: 755
    - owner: lantern

/etc/init/config-server.conf:
  file.managed:
    - source: salt://config_server/config-server.conf
    - mode: 644
    - template: jinja

config-server:
  service.running:
    - order: last
    - enable: yes
    - require:
       - service: stunnel4
    - watch:
       - file: /home/lantern/config-server.jar
       - file: /etc/init/config-server.conf
       - file: /etc/environment
       - cmd: stunnel4-deps
