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
        - sshalert
    'cm-vlfra1':
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
        - proxy_ufw_rules
    'cs-*':
        - lantern_build_prereqs
        - proxy_ufw_rules
        - config_server
