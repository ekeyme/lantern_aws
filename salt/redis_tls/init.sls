{% set files=['client_key.pem', 'client_cert.pem'] %}

{% if pillar["in_production"] %}
{% set files=files + ['redis.getlantern.org/fullchain.pem', 'redis.getlantern.org/chain.pem', 'redis.getlantern.org/cert.pem', 'redis.getlantern.org/privkey.pem'] %}
{% endif %}

{% if pillar["in_staging"] %}
{% set files=files + ['redis-staging.getlantern.org/fullchain.pem', 'redis-staging.getlantern.org/chain.pem', 'redis-staging.getlantern.org/cert.pem', 'redis-staging.getlantern.org/privkey.pem'] %}
{% endif %}

{% for file in files %}

/usr/secret/redis/{{ file }}:
  file.managed:
    - order: 2
    - source: salt://redis_tls/certs/{{ file }}
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: True

{% endfor %}
