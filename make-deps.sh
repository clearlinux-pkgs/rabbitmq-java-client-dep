#!/bin/bash

# determine the root directory of the package repo

REPO_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
if [ ! -d  "${REPO_DIR}/.git" ]; then
    2>&1 echo "${REPO_DIR} is not a git repository"
    exit 1
fi

# the first and the only argument should be the version of rabbitmq-java-client

NAME=$(basename ${BASH_SOURCE[0]})
if [ $# -ne 1 ]; then
    2>&1 cat <<EOF
Usage: $NAME <rabbitmq-java-client version>
EOF
    exit 2
fi

RJC_VERSION=$1

### move previous repository temporarily

if [ -d ${HOME}/.m2/repository ]; then
    mv ${HOME}/.m2/repository ${HOME}/.m2/repository.backup.$$
fi

### fetch the rabbitmq-java-client sources and unpack

RJC_TGZ=v${RJC_VERSION}.tar.gz

if [ ! -f "${RJC_TGZ}" ]; then
    RJC_URL=https://github.com/rabbitmq/rabbitmq-java-client/archive/${RJC_TGZ}
    if ! curl -L -o "${RJC_TGZ}" "${RJC_URL}"; then
        2>&1 echo Failed to download sources: ${RJC_URL}
        exit 1
    fi
fi

cd "${REPO_DIR}"

# assume all the files go to a subdir (so any file will give us the directory
# it's extracted to)
RJC_DIR=$(tar xzvf "${RJC_TGZ}" | head -1)
RJC_DIR=${RJC_DIR%%/*}
tar xzf "${RJC_TGZ}"

### fetch the rabbitmq-java-client depenencies and store the log (to retrieve the urls)

cd "${RJC_DIR}"

# patch it as per the rabbitmq-java-client.spec (assume files do not contain spaces)
PATCHES=$(grep ^Patch "${REPO_DIR}/../rabbitmq-java-client/rabbitmq-java-client.spec" | sed -e 's/Patch[0-9]\+\s*:\s*\(\S\)\s*/\1/')

for p in $PATCHES; do
    patch -p1 < "${REPO_DIR}/../rabbitmq-java-client/${p}"
done

make all && make tests

cd "${REPO_DIR}"

# remove previously created artifacts
rm -f sources.txt install.txt files.txt metadata-*.patch

### make the list of the dependencies
DEPENDENCIES=($(find ${HOME}/.m2/repository -type f -name \*.jar -o -name \*.pom))
METADATA=($(find ${HOME}/.m2/repository -type f -name maven-metadata\*.xml))

### create pieces of the spec (SourceXXX definitions and their install actions)

# some of the maven repositories do not allow direct download, so use single
# repository instead: https://repo1.maven.org/maven2/ . It the same as
# https://central.maven.org, but central.maven.org uses bad certificate (FQDN
# mismatch).
REPOSITORY_URL=https://repo.maven.apache.org/maven2/

SOURCES_SECTION=""
INSTALL_SECTION=""
FILES_SECTION=""
warn=
n=0

for dep in ${DEPENDENCIES[@]}; do
    dep=${dep##${HOME}/.m2/repository/}
    dep_bn=$(basename "$dep")
    dep_dn=$(dirname "$dep")
    dep_url=${REPOSITORY_URL}${dep}
    SOURCES_SECTION="${SOURCES_SECTION}
Source${n} : ${dep_url}"
    INSTALL_SECTION="${INSTALL_SECTION}
mkdir -p %{buildroot}/usr/share/rabbitmq-java-client/.m2/repository/${dep_dn}
cp %{SOURCE${n}} %{buildroot}/usr/share/rabbitmq-java-client/.m2/repository/${dep_dn}"
    FILES_SECTION="${FILES_SECTION}
/usr/share/rabbitmq-java-client/.m2/repository/${dep}"
    let n=${n}+1
done

# for each of the maven-metadata, generate a patch
if [ -n "${METADATA}" ]; then
    cd ${HOME}/.m2/repository
    n=0
    for md in ${METADATA[@]}; do
        md=${md##${HOME}/.m2/repository/}
        diff -u /dev/null "${md}" > ${REPO_DIR}/metadata-${n}.patch
        SOURCES_SECTION="${SOURCES_SECTION}
Patch${n} : metadata-${n}.patch"
        FILES_SECTION="${FILES_SECTION}
/usr/share/rabbitmq-java-client/.m2/repository/${md}"
        let n=${n}+1
    done
fi

cd "${REPO_DIR}"

echo "${SOURCES_SECTION}" | sed -e '1d' > sources.txt
echo "${INSTALL_SECTION}" | sed -e '1d' > install.txt
echo "${FILES_SECTION}" | sed -e '1d' > files.txt

cat <<EOF

sources.txt     contains SourceXXXX definitions for the spec file (including
                patches for metadata).
install.txt     contains %install section.
files.txt       contains the %files section.
EOF

if [ -n "${METADATA}" ]; then
    echo Metadata patches:
    ls -1 metadata-*.patch
fi

# restore previous .m2
rm -rf ${HOME}/.m2/repository
if [ -d ${HOME}/.m2/repository.backup.$$ ]; then
    mv ${HOME}/.m2/repository.backup.$$ ${HOME}/.m2/repository
fi

# vim: si:noai:nocin:tw=80:sw=4:ts=4:et:nu
