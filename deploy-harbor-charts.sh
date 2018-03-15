###INPUT PARA#####
PACKAGE_ROOT="/root/"
WORK_DIR="/tmp/container"
ROLLER_EXTERNAL_IP="172.100.200.56"
HABOR_ADMIN_PASSWORD="Passw0rd"

##harbor-package.tar contains harbor,image and docker-compose
HARBOR_PACKAGE="harbor_package.tar"
HARBOR_PACKAGE_MD5SUM="harbor_package.md5sum"
##chart-package.tar contains helm-client and charts
CHARTS_PACKAGE="charts_package.tar"
CHARTS_PACKAGE_MD5SUM="charts_package.md5sum"

RELEASE_DIR="/opt/registry-release"

###Pakcage dir to meet
#harbor_package.tar
#    ＼harbor_install
#                    ＼docker-compose
#                    ＼harbor.tgz
#                    ＼cube.tgz
#                    ＼captain.tgz
#                    ＼library.tgz
#harbor_package.md5sum
#charts_package.tar
#    ＼charts_install
#                    ＼chartstorage.tgz
#charts_package.md5sum



###FUNC###
function download()
{
    target_dir=$2
    file=$1
    if [ "x$file" == "x" ]; then
        return 1
    fi

    if [[ $file =~ "http" ]]; then
        echo "$file is url, use wget to download it"
        download_wget $file $target_dir
        if [ $? != 0 ]; then
            return 1
        fi
    elif [[ $file =~ "/" ]]; then
        echo "$file is local from disk, use cp to download it"
        download_local $file $target_dir
        if [ $? != 0 ]; then
            return 1
        fi
    else
        echo "$file is need to set http:xxx or https:xxx or '/', not support other source"
    fi
}

function download_wget()
{
    [[`which wget`]] || echo "wget command to exist, first install it" && return 1

    file=$1
    target_dir=$2
    file_name=$(basename $1)

    cd $target_dir

    if [ -f $target_dir/$file_name ]; then
        rm $target_dir/$file_name
    fi
    wget $file
    if [ $? != 0 ]; then
        echo "down_wget failure. and try again later"
        return 1
    fi

    cd -
}

function download_local()
{
    file=$1
    target_dir=$2
    file_name=$(basename $1)

    cd $target_dir

    if [ -f $target_dir/$file_name ]; then
        rm $target_dir/$file_name
    fi
    cp $file $target_dir/$file_name
    if [ $? != 0 ]; then
        echo "copy $file to $target_dir faillure."
        return 1
    fi
    return 0
}

function loop_download()
{
    file=$1
    file_md5sum=$2
    work_dir=$3

    if [ ! -d $work_dir ]; then
        mkdir -p $work_dir
    fi
    cd $work_dir

    attempts=3
    while [ ${attempts} -gt 0 ]; do
        download $file $work_dir
        if [ $? != 0 ]; then
            echo "download $file to $work_dir, but filure"
            sleep 30 && let attempts--
            continue
        fi
        download $file_md5sum $work_dir
        if [ $? != 0 ]; then
            echo "download $file_md5sum to $work_dir, but filure"
            sleep 30 && let attempts--
            continue
        fi

        #verify file md5sum to ensure download success.
        md5sum -c $work_dir/$(basename $file_md5sum)
        if [ $? != 0 ]; then
            echo "md5sum checksum failure."
            sleep 30 && let attempts--
            continue
        else
            echo "download success"
            break
        fi
    done
    echo ${attempts}
    if [ ${attempts} -gt 0 ]; then
        echo  "download $file $file_md5sum success"
        return 0
    fi

    echo "download $file $file_md5sum failure."
    return 1
}

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

function splite_docker_image()
{
    input=$1
    imageID=""
    ##Loaded image ID: sha256:137a07dfd084191742ebc0861606b64f5acff0f893e71348fb0c7d7aaee6a364
    ##Loaded image: 127.0.0.1/community/defaultbackend:1.0
    if [[ "${input}" =~ "Loaded image ID" ]]; then
        imageID=$(echo ${input} | awk -F 'sha256:' '{print $2}' | expr substr 1 12)
    elif [[ "${input}" =~ "Loaded image:" ]]; then
        imageID=$(echo ${input} | awk -F 'image:' '{print $2}')
    fi
    echo ${imageID}
}

function upload_docker_images()
{
    harbor_ip=$1
    harbor_admin_password=$2
    docker_images_dir=$3
    
    cd ${docker_images_dir}
    harbor_project=$(basename `pwd`)

    docker login -u admin -p $harbor_admin_password $harbor_ip >/dev/null

    echo 'upload docker images...'
    files=`ls $docker_images_dir | grep [^\/]$  | awk  '{print $NF}'`
    files=`ls $docker_images_dir | awk  '{print $NF}'`
    for file in $files
    do
        echo "upload $file"
        result=$(sudo docker load < ${file})
        image_src=`splite_docker_image "${result}"`
        if [ ${image_src} == "" ]; then
            echo "can not get imageID $file"
            continue
        fi
        echo "The image of $file: $image_src"

        name=`echo $file | awk -F '.tar' '{print $1}'`
        tag_name="$harbor_ip/$harbor_project/$name"
        sudo docker tag $image_src $tag_name
        sudo docker push $tag_name
        sudo rm -rf $docker_images_dir/$file
    done
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

loop_download ${PACKAGE_ROOT}${CHARTS_PACKAGE} ${PACKAGE_ROOT}${CHARTS_PACKAGE_MD5SUM} ${WORK_DIR}
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

#load image to harbor
cd ${WORK_DIR}/harbor_install
tar -xzf cube.tgz
cd ${WORK_DIR}/harbor_install/cube
upload_docker_images ${ROLLER_EXTERNAL_IP} ${HABOR_ADMIN_PASSWORD}  ${WORK_DIR}/harbor_install/cube

cd ${WORK_DIR}/harbor_install
tar -xzf captain.tgz
cd ${WORK_DIR}/harbor_install/captain
upload_docker_images ${ROLLER_EXTERNAL_IP} ${HABOR_ADMIN_PASSWORD}  ${WORK_DIR}/harbor_install/cube

cd ${WORK_DIR}/harbor_install
tar -xzf library.tgz
cd ${WORK_DIR}/harbor_install/library
upload_docker_images ${ROLLER_EXTERNAL_IP} ${HABOR_ADMIN_PASSWORD}  ${WORK_DIR}/harbor_install/library

#untar chart repo, bootstrap chart and load charts to harbor
cd ${WORK_DIR}
tar -xzf ${CHARTS_PACKAGE}
cd ${WORK_DIR}/charts_install/
tar -xzf chartstorage.tgz -C /opt/

docker run -d --restart=always \
  -p 8090:8090   --name=charts-repo \
  --privileged=true \
  -e PORT=8090 \
  -e DEBUG=1 \
  -e STORAGE="local" \
  -e STORAGE_LOCAL_ROOTDIR="/chartstorage" \
  -v /opt/chartstorage:/chartstorage \
  ${ROLLER_EXTERNAL_IP}/captain/chartmuseum:latest
