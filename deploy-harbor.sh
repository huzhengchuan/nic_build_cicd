#!/bin/sh
###INPUT PARA#####

##harbor-package.tar contains harbor,image and docker-compose
HARBOR_PACKAGE="harbor_package.tar"
HARBOR_PACKAGE_MD5SUM="harbor_package.md5sum"


RELEASE_DIR="/opt/registry-release"

###Pakcage dir to meet
#harbor_package.tar
#    ＼harbor_install
#                    ＼docker-compose
#                    ＼harbor.tgz
#                    ＼registry-package.tgz
#harbor_package.md5sum


source ./deploy-common.sh

###FUNC###
function config_bootstrap_harbor()
{
    REGISTRY_EXTERNAL_SERVER_IP=$1
    REGISTRY_ADMIN_PASSWORD=$2
    CONTAINER_NIC_BIN=/usr/local/bin/container-nic
    CONTAINER_NIC_SERVICE=/etc/systemd/system/container-nic.service

cat > $CONTAINER_NIC_BIN <<'EOF'
#!/bin/bash -v

echo "configure and enable harbor registry server"

harbor_install_dir="/opt/harbor/"
harbor_config_file=${harbor_install_dir}/harbor.cfg
harbor_install_file=${harbor_install_dir}/install.sh

server_ip=REGISTRY_EXTERNAL_SERVER_IP
admin_password=REGISTRY_ADMIN_PASSWORD

echo "configure harbor...."
sed -i '/^hostname = / s/=.*/='" $server_ip"'/
        /^harbor_admin_password = / s/=.*/='" $admin_password"'/
        ' ${harbor_config_file}

docker_status=$(systemctl is-active docker)
until [ ${docker_status} == "active" ]; do
    echo "wait docker work"
    sleep 5
    docker_status=$(systemctl is-active docker)
done


cd ${harbor_install_dir}

docker-compose down
sh ${harbor_install_file}


attempts=60
while [ ${attempts} -gt 0 ]; do
    status_code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1)
    if [ "${status_code}"  == "200" ]; then
        echo "habor work well"
        break
    fi
    echo "waiting for harbor work"
    sleep 5

    let attempts--
done
echo ${attempts}
if [ ${attempts} -eq 0 ]; then
    echo "habor not work well"
    exit -1
fi

EOF


cat > $CONTAINER_NIC_SERVICE <<EOF
[Unit]
Description=Container Nic
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/container-nic
[Install]
WantedBy=multi-user.target
EOF

    sed -i 's/REGISTRY_EXTERNAL_SERVER_IP/'${REGISTRY_EXTERNAL_SERVER_IP}'/g'  $CONTAINER_NIC_BIN
    sed -i 's/REGISTRY_ADMIN_PASSWORD/'${REGISTRY_ADMIN_PASSWORD}'/g'  $CONTAINER_NIC_BIN
    chown root:root $CONTAINER_NIC_BIN
    chmod 0755 $CONTAINER_NIC_BIN

    chown root:root $CONTAINER_NIC_SERVICE
    chmod 0644 $CONTAINER_NIC_SERVICE

    systemctl enable container-nic
    systemctl start --no-block container-nic
}

function wait_harbor()
{

    attempts=60
    while [ ${attempts} -gt 0 ]; do
        status_code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1)
        if [ "${status_code}"  == "200" ]; then
            echo "habor work well"
            break
        fi
        echo "waiting for harbor work"
        sleep 5

        let attempts--
    done

    if [ ${attempts} -eq 0 ]; then
        echo "habor not work well"
        return 1
    fi

}

function init_harbor()
{
    harbor_ip=$1
    harbor_admin_password=$2

    ###make captain project
    curl  -u admin:${harbor_admin_password}  \
        -H "Content-Type: application/json" -X POST \
        -d '{"project_name":"captain","public":1}'  \
        http://${harbor_ip}/api/projects
    sleep 10
    ###make cube project
    curl  -u admin:${harbor_admin_password}   \
        -H "Content-Type: application/json" -X POST \
        -d '{"project_name":"cube","public":1}'  \
        http://${harbor_ip}/api/projects

}


function init_docker()
{
    server_ip=$1

    sed -i "s/^ExecStart.*/ExecStart=\/usr\/bin\/dockerd  --log-driver=journald -H unix:\/\/\/var\/run\/docker.sock -H tcp:\/\/0.0.0.0:6732 --insecure-registry=${server_ip}/g"  \
     /usr/lib/systemd/system/docker.service


    # make sure we pick up any modified unit files
    systemctl daemon-reload

    echo "starting services"
    for service in docker; do
        echo "activating service $service"
        systemctl enable $service
        systemctl --no-block restart $service
    done
}

function image_to_harbor()
{
    cd ${WORK_DIR}
    if [ -d "/opt/docker" ]; then
        rm "/opt/docker" -rf
    fi
    tar -xzf ${WORK_DIR}/harbor_install/registry-package.tgz -C /opt/
    if [ -d "/data/registry/" ]; then
        rm "/data/registry/" -rf
    fi
    mkdir -p /data/registry/
    mv /opt/docker /data/registry/

}

########  MAIN  ########

#wget from harbor package and shasum or install from dir
if [ -d ${WORK_DIR} ]; then
    rm ${WORK_DIR} -rf
fi
mkdir -p ${WORK_DIR}

loop_download ${PACKAGE_ROOT}${HARBOR_PACKAGE}  ${PACKAGE_ROOT}${HARBOR_PACKAGE_MD5SUM}  ${WORK_DIR}
if [ $? != 0 ]; then
    exit 1
fi

#init docker
init_docker ${ROLLER_EXTERNAL_IP}

#untar harbor package and write services to systemd and start harbor
cd ${WORK_DIR}
tar -xzf ${HARBOR_PACKAGE}
mv ${WORK_DIR}/harbor_install/docker-compose /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

image_to_harbor

tar  -xzf ${WORK_DIR}/harbor_install/harbor.tgz -C /opt/
config_bootstrap_harbor ${ROLLER_EXTERNAL_IP} ${HABOR_ADMIN_PASSWORD}
if [ $? != 0 ]; then
    echo "config and bootstrap harbor failure"
    exit 1
fi

wait_harbor 
if [ $? != 0 ]; then
    echo "harbor work failure."
    exit 1
fi
#init harbor project
init_harbor ${ROLLER_EXTERNAL_IP} ${HABOR_ADMIN_PASSWORD}


systemctl start --no-block container-nic
wait_harbor
if [ $? != 0 ]; then
    echo "harbor work failure."
    exit 1
fi

