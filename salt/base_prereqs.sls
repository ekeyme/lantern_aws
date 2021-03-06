"hostname {{ grains['id'] }}":
  cmd.run:
    - order: 1
    - unless: "[ $(hostname) = {{ grains['id'] }} ]"
    - user: root
    - group: root

/etc/hosts:
  file.append:
    - order: 1
    - text: "127.0.1.1\t{{ grains['id'] }}\t{{ grains['id'] }}"

base-packages:
    pkg.installed:
        - order: 1
        - names:
            - python-software-properties
            - curl
            - python-pycurl
            - git
            - debconf-utils
            - python-psutil
            - python-dateutil
            - htop
            - vim
            - python-dev
        - reload_modules: yes

base-pips:
  pip.installed:
    - upgrade: yes
    - order: 1
    - names:
        - requests
        - subprocess32

transit-python:
  pip.installed:
    - order: 2
    - use_wheel: yes
    - pre_releases: yes

/usr/local/lib/pylib:
    file.directory:
        - order: 1
        - user: root
        - group: root
        - mode: 755
        - makedirs: yes
        - recurse:
              - user
              - group
              - mode
