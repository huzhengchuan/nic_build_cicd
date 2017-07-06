#!/usr/bin/env python

import sys
import os


host = "hub.easystack.io"
user = "admin"
password = "Passw0rd"
target_dir = "/var/www/html/k8s-images/images/"
pkg = "/var/www/html/k8s-images/images.tgz"


# Get all repositories
images = [
        "captain/pause-amd64:3.0",
        "captain/k8s-dns-kube-dns-amd64:1.10.1",
        "captain/k8s-dns-dnsmasq-amd64:1.10.1",
        "captain/k8s-dns-sidecar-amd64:1.10.1",
        "captain/hyperkube:v1.6.4",
        "captain/heapster_influxdb:v0.6",
        "captain/heapster_grafana:v4.0.2",
        "captain/heapster:v1.2.0",
        "captain/kibana:4",
        "captain/node-exporter:v0.14.0",
        "captain/prometheus:v1.6.3",
        "captain/alertmanager:v0.5.0",
        "captain/alerta-web:latest",
        "captain/mongo:latest",
        "captain/defaultbackend:1.0",
        "captain/nginx-ingress-controller:0.8.4",
        "captain/kubernetes-dashboard-amd64:v1.6.x",
        "captain/fluentd-elasticsearch:1.23",
        "captain/elasticsearch:cap2.4.4",
        ]


os.system("rm %s -rf&& mkdir %s" % (target_dir, target_dir))
os.system("rm %s -rf" % (pkg))

for image_entry in images:
    print(image_entry)
    image_url = '%s/%s' % (host, image_entry)
    os.system('docker pull %s' % image_url)
    target_url = "%s/%s" % ("hub.easystack.io", image_entry)
    os.system('docker tag %s %s' % (image_url, target_url))
    image_name = image_entry.split('/')[1] 
    target_file = "%s/%s.tar" % (target_dir, image_name)
    os.system('docker save %s > %s' % (target_url, target_file))
    print(target_file)

os.system("tar -czf %s %s" %(pkg, target_dir))
