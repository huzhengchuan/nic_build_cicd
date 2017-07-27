#!/bin/sh

#upload image data
harborIp='hub.easystack.io'
harbotProject='/captain/'
# ungzip images.tgz and put all images tar file to $docker_images_dir
docker_images_dir='/home/es/images/' 

function get_image_id()
{
    cd $1
    cp $2 tmp.tar
    mkdir tmp
    tar xvf tmp.tar -C tmp >/dev/null
    str=`cat tmp/manifest.json | awk -F 'Config":"' '{print $2}'`
    rm -rf tmp
    rm -rf tmp.tar
    cd - >/dev/null

    echo ${str:0:12}
}

function upload_docker_images()
{
    echo 'upload docker images...'
    files=`ls $docker_images_dir | grep [^\/]$  | awk  '{print $NF}'`
    files=`ls $docker_images_dir | awk  '{print $NF}'`
    for file in $files
    do
        echo "upload $file"
        sudo docker load < "$docker_images_dir"'/'"$file"
        image_id=`get_image_id $docker_images_dir $file`
        echo "The image of $file: $image_id"
        sudo docker images | grep $image_id >/dev/null

        name=`echo $file | awk -F '.tar' '{print $1}'`
        tag_name="$harborIp""$harbotProject""$name"
        sudo docker tag $image_id $tag_name
        sudo rm -rf $docker_images_dir/$file
    done
}

function clean_images()
{
    files=$(sudo docker images | grep "172.100" | awk '{position=$1":"$2; print position}')
    for file in $files
    do
        echo "clean $file"
        sudo docker rmi $file
    done

}

set -xe

upload_docker_images
clean_images
sudo docker images

