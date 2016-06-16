stunnel4:
  pkg.removed

/home/lantern/tlsproxy:
  file.managed:
    - source: salt://tlsproxy/tlsproxy
    - mode: 755
    - owner: lantern
    - require:
      - pkg: stunnel4
