#!/bin/bash
ORIGDIR=`pwd`
TMPDIR=ilbc.$$

mkdir -p ../${TMPDIR}

cd ..
cp -a libilbc ${TMPDIR}/ilbc-0.0.1
cd ${TMPDIR}
rm -rf ilbc-0.0.1/.git*
tar zcvf ilbc-0.0.1.tar.gz ilbc-0.0.1
mv ilbc-0.0.1.tar.gz ${ORIGDIR}/.

cd ${ORIGDIR}
rm -rf ../${TMPDIR}
