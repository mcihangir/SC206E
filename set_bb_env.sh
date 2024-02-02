# set_bb_env.sh
# Define macros for build targets.
# Generate bblayers.conf from get_bblayers.py.
# Some convenience macros are defined to save some typing.
# Set the build environement
if [[ ! $(readlink -f $(which sh)) =~ bash ]]
then
  echo ""
  echo "### ERROR: Please Change your /bin/sh symlink to point to bash. ### "
  echo ""
  echo "### sudo ln -sf /bin/bash /bin/sh ### "
  echo ""
  return 1
fi

# The SHELL variable also needs to be set to /bin/bash otherwise the build
# will fail, use chsh to change it to bash.
if [[ ! $SHELL =~ bash ]]
then
  echo ""
  echo "### ERROR: Please Change your shell to bash using chsh. ### "
  echo ""
  echo "### Make sure that the SHELL variable points to /bin/bash ### "
  echo ""
  return 1
fi

umask 022

# This script
THIS_SCRIPT=$(readlink -f ${BASH_SOURCE[0]})
# Find where the global conf directory is...
scriptdir="$(dirname "${THIS_SCRIPT}")"
# Find where the workspace is...
WS=$(readlink -f $scriptdir/../..)

# Find build templates from qti meta layer.
TEMPLATECONF="meta-qti-bsp/conf"

# Patch poky with QTI optimizations which not part of thud branch.
apply_poky_patches () {
    cd ${WS}/poky
    for patchfile in $(cat qti-conf/patches/series); do
        patch -p1 -N --dry-run --silent < qti-conf/patches/$patchfile > /dev/null 2>&1
        # sucessful dryrun sets exit status of last command ($?) to 0
        if [ $? -eq 0 ]; then
            #apply the patch
            patch -p1 -N --silent < qti-conf/patches/$patchfile > /dev/null 2>&1
        fi
    done
}

confnote () {
    cat <<EOF


### Shell environment ready with following configuration to run bitake commands. ###

DISTRO     = ${DISTRO}
MACHINE    = ${MACHINE}

You can now run 'bitbake <target>'

${IMAGEINFO}

EOF
}

usage () {
    cat <<EOF

Usage: [DISTRO=<DISTRO>] [MACHINE=<MACHINE>] source ${THIS_SCRIPT} [BUILDDIR]

If no MACHINE is set, list all possible machines, and ask user to choose.
If no DISTRO is set, list all possible distros, and ask user to choose.
If no BUILDDIR is set, it will be set to build-DISTRO.
If BUILDDIR is set and is already configured it is used as-is

EOF
}

# Eventually we need to call oe-init-build-env to finalize the configuration
# of the newly created build folder
init_build_env () {
    # Patch poky
    if [[ ${MACHINE} =~ "sxrneo" ]] ; then
      apply_poky_patches
    fi

    # Show conf notes
    confnote

    # Let bitbake use the following env-vars as if they were pre-set bitbake ones.
    # (BBLAYERS is explicitly blocked from this within OE-Core itself, though...)
    BB_ENV_EXTRAWHITE="DEBUG_BUILD PREBUILT_SRC_DIR"

    # Yocto/OE-core works a bit differently than OE-classic so we're
    # going to source the OE build environment setup script they provided.
    # This will dump the user in ${WS}/yocto/build, ready to run the
    # convienence function or straight up bitbake commands.
    . ${WS}/poky/oe-init-build-env ${BUILDDIR}

    # Clean up environment.
    unset MACHINE DISTRO WS usage confnote PREBUILT_SRC_DIR TEMPLATECONF THIS_SCRIPT
    unset DISTROTABLE DISTROLAYERS MACHINETABLE MACHLAYERS ITEM IMGCHOICE IMAGEINFO
}

if [ $# -gt 1 ]; then
    usage
    return 1
fi

# If BUILDIR is provided and is already a valid build folder, let's use it
if [ $# -eq 1 ]; then
    BUILDDIR="${WS}/$1"
    if [ -f "${BUILDDIR}/conf/local.conf" ] &&
           [ -f "${BUILDDIR}/conf/auto.conf" ] &&
           [ -f "${BUILDDIR}/conf/bblayers.conf" ]; then
        init_build_env
        return
    fi
fi

# Get si revision from manifest
# revision=$(xmllint --xpath '/manifest/default/@revision'  ${WS}/.repo/manifests/default.xml | sed 's/"/\t/g;' | awk '{print $2}')
# Get preferred list of machines, distros and images
# PREFMACH=`python $scriptdir/parse_imageinfo.py ${revision#refs/heads/} machine`
# PREFDIST=`python $scriptdir/parse_imageinfo.py ${revision#refs/heads/} distro`
# PREFIMAG=`python $scriptdir/parse_imageinfo.py ${revision#refs/heads/} target`

PREFMACH=qrbx210-rbx
PREFDIST="qti-distro-rb-debug qti-distro-rb-perf"
PREFIMAG="qti-robotics-med-image qti-robotics-image "

# Choose one among whiptail & dialog to show dialog boxes
read uitool <<< "$(which whiptail dialog 2> /dev/null)"

# create a common list of "<machine>(<layer>)", sorted by <machine>
MACHLAYERS=$(cd ${WS}/poky && find meta-qti-bsp -print | grep "/conf/machine/.*\.conf" | grep -v "fsconfig" | grep -v "partition" | sed -e 's/\.conf//g' | awk -F'/conf/machine/' '{print $NF "(" $1 ")"}' | LANG=C sort)

if [ -n "${MACHLAYERS}" ] && [ -z "${MACHINE}" ]; then
    for ITEM in $MACHLAYERS; do
        if [[ $PREFMACH == *$(echo "$ITEM" |cut -d'(' -f1)* ]]; then
            MACHINETABLE="${MACHINETABLE} $(echo "$ITEM" | cut -d'(' -f1) $(echo "$ITEM" | cut -d'(' -f2 | cut -d')' -f1)"
        fi
    done
    if [ -n "${MACHINETABLE}" ]; then
        MACHINETABLE="${MACHINETABLE} Show-All-Machines From-All-BSP-Layers"
        MACHINE=$($uitool --title "Preferred Machines" --menu \
            "Please choose a machine" 0 0 20 \
            ${MACHINETABLE} 3>&1 1>&2 2>&3)
        if [ "$MACHINE" == "Show-All-Machines" ]; then
            MACHINE=""
            MACHINETABLE=""
        fi
    fi
    if [ -z "${MACHINE}" ]; then
       for ITEM in $MACHLAYERS; do
           MACHINETABLE="${MACHINETABLE} $(echo "$ITEM" | cut -d'(' -f1) $(echo "$ITEM" | cut -d'(' -f2 | cut -d')' -f1)"
       done
       MACHINE=$($uitool --title "Available Machines" --menu \
           "Please choose a machine" 0 0 20 \
           ${MACHINETABLE} 3>&1 1>&2 2>&3)
    fi
fi

# create a common list of "<distro>(<layer>)", sorted by <distro>
DISTROLAYERS=$(cd ${WS}/poky && find meta-qti-distro -print | grep "conf/distro/.*\.conf" | sed -e 's/\.conf//g' | awk -F'/conf/distro/' '{print $NF "(" $1 ")"}' | LANG=C sort)

if [ -n "${DISTROLAYERS}" ] && [ -z "${DISTRO}" ]; then
    for ITEM in $DISTROLAYERS; do
        if [[ $PREFDIST == *$(echo "$ITEM" |cut -d'(' -f1)* ]]; then
            DISTROTABLE="${DISTROTABLE} $(echo "$ITEM" | cut -d'(' -f1) $(echo "$ITEM" | cut -d'(' -f2 | cut -d')' -f1)"
        fi
    done
    if [ -n "${DISTROTABLE}" ]; then
        DISTROTABLE="${DISTROTABLE} Show-All-Distros From-All-Distro-Layers"
        DISTRO=$($uitool --title "Preferred Distributions" --menu \
            "Please choose a distribution" 0 0 20 \
            ${DISTROTABLE} 3>&1 1>&2 2>&3)
        if [ "$DISTRO" == "Show-All-Distros" ]; then
            DISTRO=""
            DISTROTABLE=""
        fi
    fi
    if [ -z "${DISTRO}" ]; then
        for ITEM in $DISTROLAYERS; do
            DISTROTABLE="${DISTROTABLE} $(echo "$ITEM" | cut -d'(' -f1) $(echo "$ITEM" | cut -d'(' -f2 | cut -d')' -f1)"
        done
        DISTRO=$(whiptail --title "Available Distributions" --menu \
            "Please choose a distribution" 0 0 20 \
            ${DISTROTABLE} 3>&1 1>&2 2>&3)
    fi
fi

# If nothing has been set, go for 'nodistro'
if [ -z "$DISTRO" ]; then
    DISTRO="nodistro"
fi

# Image menu choices
IMGCHOICE=$(echo $PREFIMAG | tr " " "\n")
if [ -n "${IMGCHOICE}" ]; then
   IMAGEINFO=$(printf 'Supported image targets are:\n%s' "$IMGCHOICE")
fi

# guard against Ctrl-D or cancel
if [ -z "$MACHINE" ]; then
    echo "To choose a machine interactively please install whiptail or dialog."
    echo "To choose a machine non-interactively please use the following syntax:"
    echo "    MACHINE=<your-machine> source ${THIS_SCRIPT}"
    echo ""
    echo "Press <ENTER> to see a list of your choices"
    read -r
    echo "$MACHLAYERS" | sed -e 's/(/ (/g' | sed -e 's/)/)\n/g' | sed -e 's/^ */\t/g'
    return
fi

# we can be called with only 1 parameter max, <build> folder, or default to build-$distro
BUILDDIR="${WS}/build-$DISTRO"
if [ $# -eq 1 ]; then
    BUILDDIR="${WS}/$1"
fi

mkdir -p "${BUILDDIR}"/conf

# BBLAYERS (by OE-Core class policy...Bitbake understands it...) to support
# dynamic workspace layer functionality.
if [[ ${MACHINE} =~ "sxrneo" ]] ; then
   python $scriptdir/get_bblayers.py \"meta*\" --lookup-paths ${WS}/poky --with-layer-check >| ${BUILDDIR}/conf/bblayers.conf
elif [[ ${MACHINE} =~ "trustedvm" ]] ; then
    python $scriptdir/get_bblayers.py \"meta*\" --lookup-paths ${WS}/poky ${WS}/src/display ${WS}/src/display/vendor/qcom/proprietary >| ${BUILDDIR}/conf/bblayers.conf
else
   python $scriptdir/get_bblayers.py \"meta*\" --lookup-paths ${WS}/poky >| ${BUILDDIR}/conf/bblayers.conf
fi

# local.conf
cat >| ${BUILDDIR}/conf/local.conf <<EOF
# This configuration file is dynamically generated every time
# set_bb_env.sh is sourced to set up a workspace.  DO NOT EDIT.
#--------------------------------------------------------------
EOF
cat $scriptdir/local.conf >> ${BUILDDIR}/conf/local.conf

# Read manifest tag to set BUILDNAME and SDK_VERSION
# ${BUILDNAME} is used to set the content of /etc/version
BUILDNAME="QRBX210.LE.1.0-00018-STD.PROD-2"
BUILDVERSION="r1.0_00012.0"

# auto.conf
cat >| ${BUILDDIR}/conf/auto.conf <<EOF
# This configuration file is dynamically generated every time
# set_bb_env.sh is sourced to set up a workspace.  DO NOT EDIT.
#--------------------------------------------------------------
DISTRO ?= "${DISTRO}"
MACHINE ?= "${MACHINE}"
SSTATE_DIR ?= "${BUILDDIR}/sstate-cache"
#DL_DIR = "${WS}/downloads"
DL_DIR = "/opt/downloads-qcm2290"
BUILDNAME = "${BUILDNAME}"
SDK_VERSION = "${BUILDVERSION}"
BB_NUMBER_THREADS = "4" 
PARALLEL_MAKE = "-j 4"
EOF

function build-qti-robotics-med-image() {
    export  DISTRO=qti-distro-rb-debug
    bitbake qti-recovery-image && \
    bitbake qti-robotics-med-image
}

function build-qti-robotics-med-image-user-security() {
    export  DISTRO=qti-distro-rb-user-security
    bitbake qti-recovery-image && \
    bitbake qti-robotics-med-image
}

function build-qti-robotics-med-image-perf() {
    export  DISTRO=qti-distro-rb-perf
    bitbake qti-recovery-image && \
    bitbake qti-robotics-med-image
}

TARGET_IMG_DIR="${BUILDDIR}/tmp-glibc/work/qrbx210_rbx-oe-linux/qti-robotics-med-image/1.0-r0/"

makeboot() {
    bitbake -c do_makeboot qti-robotics-med-image
    echo ""
    echo "boot.img in ${TARGET_IMG_DIR}/deploy-qti-robotics-med-image-bootimage-complete/qti-robotics-med-image/boot.img"
    echo ""
}

makesystem() {
    bitbake -c do_makesystem qti-robotics-med-image
    echo ""
    echo "system.img in ${TARGET_IMG_DIR}/deploy-qti-robotics-med-image-image-complete/qti-robotics-med-image/system.img"
    echo ""
}

buildclean() {
    set -x
    cd ${BUILDDIR}
    rm -rf bitbake.lock buildhistory sstate-cache tmp-glibc/* cache && cd - || cd -
    set +x
}

rebake() {
    bitbake -c cleansstate $@ && \
    bitbake $@
}

# Force error for dangling bbappends
if [[ ${MACHINE} =~ "sxrneo" ]] ; then
   echo 'BB_DANGLINGAPPENDS_WARNONLY_forcevariable = "false"' >> ${BUILDDIR}/conf/auto.conf
fi

# Check and run pre-configs from enabled meta layers
layerstring=$( \
while read line; do \
  if [[ $line =~ BBLAYER ]] ; then echo $line | cut -f2 -d"="; fi \
done < ${BUILDDIR}/conf/bblayers.conf \
)

for layer in ${layerstring//\"}; do
  if [ -f "$layer/scripts/set_env.sh" ]; then
    source $layer/scripts/set_env.sh
  fi
done


# Finalize
init_build_env
