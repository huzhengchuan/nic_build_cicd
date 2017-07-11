#!/bin/sh

#upload image data
harborIp='192.168.122.197'
harbotProject='/captain/'
docker_images_dir='/home/centos/config/google_containers-3.4.6/'
harbor_admin_password='Passw0rd'
harbor_admin_email='user@example.com'
app_images_dir='/home/centos/config/test_app/'
appProject='/library/'

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
    docker login -u admin -p $harbor_admin_password -e $harbor_admin_email $harborIp >/dev/null
    files=`ls $docker_images_dir | grep [^\/]$  | awk  '{print $NF}'`
    files=`ls $docker_images_dir | awk  '{print $NF}'`
    for file in $files
    do
        echo "upload $file"
        docker load < "$docker_images_dir"'/'"$file"
        image_id=`get_image_id $docker_images_dir $file`
        echo "The image of $file: $image_id"
        docker images | grep $image_id >/dev/null

        name=`echo $file | awk -F '.tar' '{print $1}'`
        tag_name="$harborIp""$harbotProject""$name"
        docker tag $image_id $tag_name
        docker push $tag_name
    done
}


function upload_app_images()
{
    echo 'upload app images...'
    docker login -u admin -p $harbor_admin_password -e $harbor_admin_email $harborIp >/dev/null
    files=`ls $docker_images_dir | grep [^\/]$  | awk  '{print $NF}'`
    files=`ls $docker_images_dir | awk  '{print $NF}'`
    for file in $files
    do
        echo "upload $file"
        docker load < "$app_images_dir"'/'"$file"
        image_id=`get_image_id $app_images_dir $file`
        echo "The image of $file: $image_id"
        docker images | grep $image_id >/dev/null

        name=`echo $file | awk -F '.tar' '{print $1}'`
        tag_name="$harborIp""$appProject""$name"
        docker tag $image_id $tag_name
        docker push $tag_name
    done
}

set -xe

upload_docker_images
upload_app_images
docker images
