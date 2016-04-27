#!/usr/bin/env python


import os
import time

from redis_util import redis_shell
import redisq
import vps_util


TIMEOUT = 5 * 60


def run():
    region = vps_util.my_region()
    print "Starting offload server for region %s." % region
    qname = region + ":offloadq"
    q = redisq.Queue(qname, redis_shell, TIMEOUT)
    while True:
        task, remover = q.next_job()
        if task:
            name, ip = task.split('|')
            txn = redis_shell.pipeline()
            vps_util.actually_offload_proxy(name, ip, txn)
            remover(txn)
            cm = vps_util.cm_by_name(name)
            txn.lpush(cm + ':retireq', task)
            txn.execute()
        else:
            time.sleep(10)


if __name__ == '__main__':
    run()
