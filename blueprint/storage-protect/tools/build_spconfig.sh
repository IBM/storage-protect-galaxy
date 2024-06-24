#!/bin/bash
# This script builds .tar.gz and .zip packages of the blueprints
# Usage:  sudo ./build_spconfig.sh 51b
VERSION=$1

BLDTMP="/tmp/spconfigbuildtmp"
RELEASES="./releases"
RESOURCES="./resources"
RESPONSES="./response-files"
TOOLS="./sp-load-generator"

echo "Validating complete git extract of blueprint files"
if [ ! -d $RELEASES ]; then
  echo "ERROR: Missing directory $RELEASES"
  exit
fi
if [ ! -d $RESOURCES ]; then
  echo "ERROR: Missing directory $RESOURCES"
  exit
fi
if [ ! -d $RESPONSES ]; then
  echo "ERROR: Missing directory $RESPONSES"
  exit
fi
if [ ! -d $TOOLS ]; then
  echo "ERROR: Missing directory $TOOLS"
  exit
fi
echo "Validation of git extract completed successfully"

if [ -d $BLDTMP ]; then
  echo "ERROR: You must first remove a conflicting directory $BLDTMP"
  exit
fi

echo "Copy files to correct locations in $BLDTMP/spconfig"
mkdir $BLDTMP
mkdir $BLDTMP/sp-config
chmod 555 $BLDTMP/sp-config
cp ./sp_cleanup.pl $BLDTMP/sp-config/
cp ./sp_config.pl $BLDTMP/sp-config/
cp $TOOLS/sp_disk_load_gen.pl $BLDTMP/sp-config/
cp $BLDTMP/sp-config/sp_disk_load_gen.pl tsmdiskperf.pl
cp $TOOLS/sp_client_load_gen.pl $BLDTMP/sp-config/
cp $TOOLS/storage_prep_aix.pl $BLDTMP/sp-config/
cp $TOOLS/storage_prep_lnx.pl $BLDTMP/sp-config/
cp $TOOLS/storage_prep_win.pl $BLDTMP/sp-config/
cp -r $TOOLS/bin $BLDTMP/sp-config/
chmod -R 555 $BLDTMP/sp-config/bin/*
mkdir $BLDTMP/sp-config/resources
chmod 555 $BLDTMP/sp-config/resources
cp $RESOURCES/* $BLDTMP/sp-config/resources/
mkdir $BLDTMP/sp-config/response-files
chmod 555 $BLDTMP/sp-config/response-files
cp $RESPONSES/* $BLDTMP/sp-config/response-files/

PREVDIR=$(pwd)
cd $BLDTMP

WINPKG="releases/sp-config_v$VERSION.zip"
echo "Create Windows .zip package in $WINPKG"
zip -r $PREVDIR/$WINPKG sp-config

UNXPKG="releases/sp-config_v$VERSION.tar"
echo "Create Unix .tar.gz package in $UNXPKG"
dos2unix $PREVDIR/*.pl
dos2unix $PREVDIR/resources/*
dos2unix $PREVDIR/response-files/*
tar -cvf $PREVDIR/$UNXPKG sp-config
gzip $PREVDIR/$UNXPKG
UNXPKG=$UNXPKG".gz"

cd $PREV
rm -rf $BLDTMP

echo
echo "---------------------------------------------------"
echo "Build completed"
echo "Windows: $WINPKG"
echo "Unix: $UNXPKG"


