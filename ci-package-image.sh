#!/bin/sh

RELEASE_DIR="/opt/registry-release"


function systemcheck()
{
    image_list=$1

    res=$(docker info | grep "hub.easystack.io")
    if [ -z "$res" ]; then
        echo "检查hub.easystack.io"
        echo "检查docker是否安装"
        echo "docker的insecurity registry是否配置hub.easystack.io"
        return 1
    fi

    if [ ! -f "$image_list" ]; then
        echo "$image_list is not exist"
        return 1
    fi
    return 0
}

function install_registry()
{
    ##安装docker registry,安装前check是否有之前的registry残留数据以及container
    container_id=$(docker ps -a | grep ci-release-registry | awk '{print $1}')
    if [ -n "$container_id" ]; then
        docker rm ci-release-registry -f -v
    fi

    host_storage_dir="/mnt/ci-release-registry"
    if [ -d "${host_storage_dir}" ]; then
        rm -rf ${host_storage_dir}
        mkdir -p ${host_storage_dir}
    fi

    docker run -d -p 5010:5000 --restart=always --name ci-release-registry \
        -v $host_storage_dir:/var/lib/registry  hub.easystack.io/library/registry:v2

    container_id=$(docker ps  | grep ci-release-registry | awk '{print $1}')
    if [ -z "$container_id" ]; then
        echo "registry bootstrap failed"
        return 1
    fi
}


function imagestoregistry()
{
    image_list=$1
    while read image
    do
        echo "work on $image"
        docker pull $image
        ##hub.easystack.io/library/xxx:test
        dest_image=$(echo $image | sed 's/hub.easystack.io/127.0.0.1:5010/g')
        docker tag $image $dest_image
        docker push $dest_image
        echo "push $image to registry $dest_image"
    done <$image_list
}

function packageregistry()
{
    docker stop ci-release-registry
    cd /mnt/ci-release-registry
    tar -czf registry-package.tgz docker
    if [ -d "$RELEASE_DIR" ]; then
        rm -rf $RELEASE_DIR
    fi
    mkdir -p $RELEASE_DIR

    mv registry-package.tgz $RELEASE_DIR
    cd $RELEASE_DIR
    md5sum registry-package.tgz > registry-package.md5sum
}


####MAIN#####
image_list=$1
systemcheck $image_list
if [ $? != 0 ]; then
    exit -1
fi

install_registry
if [ $? != 0 ]; then
    echo "install registry failed"
    exit -1
fi

imagestoregistry $image_list

packageregistry

