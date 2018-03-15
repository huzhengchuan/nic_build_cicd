#!/bin/sh
###INPUT PARA#####
##chart-package.tar contains helm-client and charts
CHARTS_PACKAGE="charts_package.tar"
CHARTS_PACKAGE_MD5SUM="charts_package.md5sum"

RELEASE_DIR="/opt/registry-release"

###Pakcage dir to meet
#charts_package.tar
#    ＼charts_install
#                    ＼chartstorage.tgz
#charts_package.md5sum

source ./deploy-common.sh

#wget from harbor package and shasum or install from dir
if [ -d ${WORK_DIR} ]; then
    rm ${WORK_DIR} -rf
fi
mkdir -p ${WORK_DIR}


loop_download ${PACKAGE_ROOT}${CHARTS_PACKAGE} ${PACKAGE_ROOT}${CHARTS_PACKAGE_MD5SUM} ${WORK_DIR}
if [ $? != 0 ]; then
    exit 1
fi

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
