#!/bin/sh

PACKAGE_ROOT="/root/"
WORK_DIR="/tmp/container"
ROLLER_EXTERNAL_IP="172.100.200.56"
HABOR_ADMIN_PASSWORD="Passw0rd"

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