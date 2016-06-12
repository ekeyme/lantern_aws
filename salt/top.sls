base:
    '*':
        - base_prereqs
        - ulimits
        - pip
        - security
        - lantern_administrators
        - unattended_upgrades
        - locales
        - enable_swap
        - timezone
        - monitor
        - reboot
        - pylib
        - env
        - stats
        - logrotate
        - check_disk
        - netdata
        - redis
        - redis_tls
        - sshalert
    'cm-donyc3':
        - vps_sanity_checks
        - check_vpss
        - update_masquerades
    'cm-*':
        - salt_cloud
        - cloudmaster
        - checkfallbacks
    'fp-*':
        - lantern_build_prereqs
        - apt_upgrade
        - http_proxy
    'pubsub-*':
        - pubsub
    'borda-*':
        - borda
    'ops-panel':
        - lantern_build_prereqs
        - default_ufw_rules
    'cs-*':
        - lantern_build_prereqs
        - default_ufw_rules
        - stunnel4
        - config_server
    'redis-*':
        - stunnel4
        - redis_server
