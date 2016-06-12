{% set proxy_protocol=pillar.get('proxy_protocol', 'tcp') %}

/etc/ufw/applications.d/lantern:
    file.managed:
        - source: salt://default_ufw_rules/ufw_rules
        - template: jinja
        - context:
            proxy_protocol: {{ proxy_protocol }}
        - user: root
        - group: root
        - mode: 644

open-proxy-port:
    cmd.run:
        - name: "ufw allow lantern_proxy"
        - require:
            - file: /etc/ufw/applications.d/lantern

/etc/default/ufw:
    file.replace:
        - pattern: '^DEFAULT_FORWARD_POLICY="DROP"$'
        - repl:     'DEFAULT_FORWARD_POLICY="ACCEPT"'

/etc/ufw/sysctl.conf:
    file.append:
        - text: |
            net/ipv4/ip_forward=1
            net/ipv6/conf/default/forwarding=1
{% if proxy_protocol == 'tcp' %}
/etc/ufw/before.rules:
    file.append:
        - text: |
            *nat
            :PREROUTING ACCEPT - [0:0]
            # Redirect ports 80 and 443 to the Lantern proxy
            -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 62000
            -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 62443

            COMMIT
{% endif %}

ufw-rules-ready:
    cmd.run:
        - name: 'service ufw restart'
        - user: root
        - group: root
        - require:
            - cmd: open-proxy-port
        - watch:
            - file: /etc/ufw/applications.d/lantern
            - file: /etc/default/ufw
            - file: /etc/ufw/sysctl.conf
{% if proxy_protocol == 'tcp' %}
            - file: /etc/ufw/before.rules
{% endif %}
