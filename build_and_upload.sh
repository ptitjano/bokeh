#!/bin/bash

if [ "$1" == "-h" ]; then
    usage="$(basename "$0") [-h] [--tag] -- program to build and upload bokeh pkgs to binstar

    where:
        -h     show this help text

        -t     the tag in the form X.X.X-devel[rc]
        -u     RackSpace username
        -k     RackSpace APIkey
    "
    echo "$usage"
    exit 0
fi

while getopts t:i:u:k: option;
do
    case "${option}" in
        t) tag=${OPTARG};;
        u) username=${OPTARG};;
        k) key=$OPTARG;;
    esac 
done

#get user and key from env variables if they are not provided with args
if [ "$username" == "" ]; then
    username=$BOKEH_DEVEL_USERNAME
    echo "$username"
fi

if [ "$key" == "" ]; then
    key=$BOKEH_DEVEL_APIKEY
    echo "$key"
fi

# tag the branch
git tag -a $tag -m 'devel'

# get version number
version=`python scripts/get_bump_version.py`

# exit if there is no new tag
if [ "$version" == "No X.X.X-devel[rc] tag." ]; then
    echo You need to tag using the X.X.X-devel"[rc]" form before building.
    # delete the tag
    git tag -d $tag
    exit 0
fi

# build for each python version
for py in 27 33 34;
do
    echo "Building py$py pkg"
    CONDA_PY=$py conda build conda.recipe --quiet
done

# get conda info about root_prefix and platform
function conda_info {
    conda info --json | python -c "import json, sys; print(json.load(sys.stdin)['$1'])"
}

CONDA_ENV=$(conda_info root_prefix)
PLATFORM=$(conda_info platform)
BUILD_PATH=$CONDA_ENV/conda-bld/$PLATFORM

# convert to platform-specific builds
conda convert -p all -f $BUILD_PATH/bokeh*$version*.tar.bz2;

#upload conda pkgs to binstar
array=(osx-64 linux-64 win-64 linux-32 win-32)
for i in "${array[@]}"
do
    echo Uploading: $i;
    #binstar upload -u bokeh $i/bokeh*$version*.tar.bz2 -c dev --force;
done

#create and upload pypi pkgs to binstar
#zip is currently not working

BOKEH_DEV_VERSION=$version python setup.py sdist --formats=gztar
#binstar upload -u bokeh dist/bokeh*$version* --package-type pypi -c dev --force;

echo "I'm done uploading to binstar"

#general clean up

#delete the tag
git tag -d $tag

#clean up platform folders
for i in "${array[@]}"
do
    rm -rf $i
done

rm -rf dist/
rm -rf build/
rm -rf bokeh.egg-info/
rm -rf record.txt
rm -rf __conda_version__.txt
rm -rf bokeh/__conda_version__.py

#upload js and css to the cdn

#get token
token=`curl -s -XPOST https://identity.api.rackspacecloud.com/v2.0/tokens \
-d'{"auth":{"RAX-KSKEY:apiKeyCredentials":{"username":"'$username'","apiKey":"'$key'"}}}' \
-H"Content-type:application/json" | python -c 'import sys,json;data=json.loads(sys.stdin.read());print(data["access"]["token"]["id"])'`

#get unique url id
id=`curl -s -XPOST https://identity.api.rackspacecloud.com/v2.0/tokens \
-d'{"auth":{"RAX-KSKEY:apiKeyCredentials":{"username":"'$username'","apiKey":"'$key'"}}}' \
-H"Content-type:application/json" | python -c 'import sys,json;data=json.loads(sys.stdin.read());print(data["access"]["serviceCatalog"][-1]["endpoints"][0]["tenantId"])'`

#push the js and css files
curl -XPUT -T bokehjs/build/js/bokeh.js -v -H "X-Auth-Token:$token" -H "Content-Type: text/plain" \
"https://storage101.dfw1.clouddrive.com/v1/$id/bokeh/bokeh.$version.js";
curl -XPUT -T bokehjs/build/js/bokeh.min.js -v -H "X-Auth-Token:$token" -H "Content-Type: text/plain" \
"https://storage101.dfw1.clouddrive.com/v1/$id/bokeh/bokeh.$version.min.js";
curl -XPUT -T bokehjs/build/css/bokeh.css -v -H "X-Auth-Token:$token" -H "Content-Type: text/plain" \
"https://storage101.dfw1.clouddrive.com/v1/$id/bokeh/bokeh.$version.css";
curl -XPUT -T bokehjs/build/css/bokeh.min.css -v -H "X-Auth-Token:$token" -H "Content-Type: text/plain" \
"https://storage101.dfw1.clouddrive.com/v1/$id/bokeh/bokeh.$version.min.css";

echo "I'm done uploading to Rackspace"

########################
####Removing on binstar#
########################


# remove entire release
# binstar remove user/package/release
# binstar --verbose remove bokeh/bokeh/0.4.5.dev.20140602

# remove file
# binstar remove user[/package[/release/os/[[file]]]]
# binstar remove bokeh/bokeh/0.4.5.dev.20140602/linux-64/bokeh-0.4.5.dev.20140602-np18py27_1.tar.bz2

# show files
# binstar show user[/package[/release/[file]]]
# binstar show bokeh/bokeh/0.4.5.dev.20140604
