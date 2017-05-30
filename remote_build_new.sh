#!/bin/bash

# this script copyies stuff to VM and run build on VM

set -x

echo "target is $target"
rm -rf $pre_repo_dir/$target/$image
mkdir -p $pre_repo_dir/$target/SRC
mkdir -p $pre_repo_dir/$target/$image

export work_dir="MaxScale"
export orig_image=$image

if [ "$product_name" == "" ] ; then
	export product_name="maxscale"
fi

if [ ! -d "BUILD" ] ; then
	cp -r ~/build-scripts/build/$product/BUILD .
fi

echo $sshuser
echo $platform
echo $platform_version

ssh $sshopt "sudo rm -rf $work_dir"
echo "copying stuff to $image machine"
ssh $sshopt "mkdir -p $work_dir"

rsync -avz  --progress --delete -e "ssh $scpopt" ./* $sshuser@$IP:$work_dir/ 
if [ $? -ne 0 ] ; then
        echo "Error copying stuff to $image machine"
        exit 2
fi

export install_script="install_build_deps.sh"

if [ "$image_type" == "RPM" ] ; then
	build_script="build_rpm_local.sh"
	files="*.rpm"
	tars="$product_name*.tag.gz"
else
	build_script="build_deb_local.sh"
	files="../*.deb"
	tars="$product_name*.tag.gz"
fi

if [ "$already_running" != "ok" ] ; then
	export already_running="false"
fi

export remote_build_cmd="export already_running=\"$already_running\"; \
	export use_mariadbd=\"$use_mariadbd\"; \
	export build_experimental=\"$build_experimental\"; \
	export cmake_flags=\"$cmake_flags\"; \
	export work_dir=\"$work_dir\"; \
	export remove_strip=\"$remove_strip\"; \
	export platform=\"$platform\"; \
	export platform_version=\"$platform_version\"; \
	export source=\"$scm_source\"; \
	export BUILD_TAG=\"$BUILD_TAG\"; \
	"

if [ "$already_running" != "ok" ]
then
    echo "install packages on $image"
    ssh $sshopt "$remote_build_cmd ./MaxScale/BUILD/$install_script"
    installres=$?

    if [ $installres -ne 0 ]
    then
        exit $installres
    fi

    dir1=`pwd`
    cd ~/mdbci
    ./mdbci snapshot take --path-to-nodes $box --snapshot-name clean
    cd $dir1
else
	echo "already running VM, not installing deps"
fi

echo "run build on $image"
ssh $sshopt "$remote_build_cmd ./MaxScale/BUILD/$build_script"
if [ $? -ne 0 ] ; then
        echo "Error build on $image"
        exit 4
fi

if [ "$no_repo" != "yes" ] ; then
	echo "copying repo to the repo/$target/$image"
	scp $scpopt $sshuser@$IP:$work_dir/$files $pre_repo_dir/$target/$image
	scp $scpopt $sshuser@$IP:$work_dir/$tars $pre_repo_dir/$target/$image
fi

echo "package building for $target done!"

if [ "$no_repo" != "yes" ] ; then
	~/build-scripts/create_remote_repo.sh $image $IP $target
fi
