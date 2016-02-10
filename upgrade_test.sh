#!/bin/bash

set -x

export work_dir=`pwd`

cd ~/mdbci

provider=`./mdbci show provider $box --silent 2> /dev/null`
datestr=`date +%Y%m%d-%H%M`
name="install_$box-$datestr"
cp ~/build-scripts/install.$provider.json ~/mdbci/$name.json

sed -i "s/###box###/$box/g" ~/mdbci/$name.json

while [ -f ~/vagrant_lock ]
do
	sleep 5
done
touch ~/vagrant_lock

# destroying existing box
cd ~/mdbci
if [ -d "install_$box" ]; then
	cd $name
	vagrant destroy -f
	cd ..
fi

cd $work_dir
~/mdbci-repository-config/generate_all.sh repo.d
~/mdbci-repository-config/maxscale-ci.sh $old_target repo.d
cd ~/mdbci

# starting VM for build
./mdbci --override --template $name.json --repo-dir $work_dir/repo.d generate $name 
./mdbci up $name
if [ $? != 0 ] ; then
	echo "Error starting VM"
	cd $name
	vagrant destroy -f
	rm ~/vagrant_lock
	exit 1
fi

rm ~/vagrant_lock


cd $work_dir
rm -rf repo.d
~/mdbci-repository-config/generate_all.sh repo.d
~/mdbci-repository-config/maxscale-ci.sh $new_target repo.d

cd ~/mdbci

./mdbci setup_repo --product maxscale --repo-dir $work_dir/repo.d $name/maxscale
./mdbci install_product --product maxscale $name/maxscale


res=$?
cd ~/mdbci/$name
if [ "x$do_not_destroy_vm" != "xyes" ] ; then
	vagrant destroy -f
fi
exit $res
