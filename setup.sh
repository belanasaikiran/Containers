#!/usr/bin/env bash

# Intel® Acceleration Stack for FPGAs installer

# Copyright 2018-2020 Intel Corporation. All rights reserved.

# Your use of Intel Corporation's design tools, logic functions and other
# software and tools, and its AMPP partner logic functions, and any output files
# any of the foregoing (including device programming or simulation files), and
# any associated documentation or information are expressly subject to the terms
# and conditions of the Intel Program License Subscription Agreement, Intel
# MegaCore Function License Agreement, or other applicable license agreement,
# including, without limitation, that your use is for the sole purpose of
# programming logic devices manufactured by Intel and sold by Intel or its
# authorized distributors.  Please refer to the applicable agreement for
# further details.

################################################################################
# Global variables
################################################################################
PKG_TYPE="rte"

QUARTUS_VERSION="19.2"
QUARTUS_BASE_VERSION_BUILD="${QUARTUS_VERSION}.0.57"
QUARTUS_UPDATE_VER="0"
QUARTUS_BUILD="57"
QUARTUS_UPDATE_VERSION_BUILD="${QUARTUS_VERSION}.${QUARTUS_UPDATE_VER}.${QUARTUS_BUILD}"
AOCL_VERSION="19.4.0.64"

if [ "$PKG_TYPE" = "dev" ] ;then
    PRODUCT_NAME="Intel® Acceleration Stack for Intel® Xeon® CPU with FPGAs Development Package"
    PRODUCT_DIR="inteldevstack"

    QUARTUS_DEFAULT_INSTALLDIR="/opt/intelFPGA_pro/quartus_${QUARTUS_VERSION}.${QUARTUS_UPDATE_VER}b${QUARTUS_BUILD}"
    QUARTUS_INSTALLER="QuartusProSetup-${QUARTUS_BASE_VERSION_BUILD}-linux.run"
    QUARTUS_UPDATE=""
    AOCL_INSTALLER="AOCLProSetup-${AOCL_VERSION}-linux.run"
    declare -a patches=("0.01rc")

    qproduct="quartus"
    qproduct_env="QUARTUS_HOME"

    opencl="hld"
    opencl_dev_env="INTELFPGAOCLSDKROOT"
    opencl_alt_dev_env="ALTERAOCLSDKROOT"

else
    PRODUCT_NAME="Intel® Acceleration Stack for Intel® Xeon® CPU with FPGAs Runtime Package"
    PRODUCT_DIR="intelrtestack"

    QUARTUS_DEFAULT_INSTALLDIR="/opt/opencl_rte"
    QUARTUS_UPDATE=""
    AOCL_INSTALLER="aocl-pro-rte-${AOCL_VERSION}-linux.run"
    declare -a patches=()

    qproduct="aclrte-linux64"
    qproduct_env="INTELFPGAOCLSDKROOT"
    opencl_alt_dev_env="ALTERAOCLSDKROOT"

fi

prompt_opae=1
install_opae=1

prompt_pacsign=1
install_pacsign=1

DEFAULT_INSTALLDIR="$HOME/$PRODUCT_DIR"

DCP_INSTALLER="a10_gx_pac_ias_1_2_1_pv.tar.gz"

OPAE_VER="1.1.2-2"
DRIVER_VER="2.0.3-3"
ADMIN_VER="1.0.2-3"
PACSIGN_VER="1.0.3-1"
SUPER_RSU_VER="1.2.1-13"
OTSU_VER="1.2.1-13"

SUPPORTED_CENTOS_VERSION="7.6"
SUPPORTED_CENTOS_KERNEL_VERSION="3.10"
SUPPORTED_UBUNTU_VERSION="18.04"

################################################################################
# Parse command-line options
################################################################################

INSTALLDIR=''
DCP_LOC=''
YESTOALL=0
DRYRUN=0

POSITIONAL=()
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        --installdir) # to specify the directory to install Quartus/OpenCL software
            INSTALLDIR="$2"
            shift # past argument
            shift # past value
            ;;
        --dcp_loc) # to specify the directory to install Intel® Acceleration Stack for FPGAs, default is same as the installdir
            DCP_LOC="$2"
            shift # past argument
            shift # past value
            ;;
         --yes) # default to yes for all the prompts
            YESTOALL=1
            shift # past argument
            ;;
         --dryrun)
            DRYRUN=1 # dry run - without actually executing the commands
            shift # past argument
            ;;
        *)    # unknown option
            POSITIONAL+=("$1") # save it in an array for later
            shift # past argument
            ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


################################################################################
# Functions to support try/catch exceptions
################################################################################

function try()
{
    [[ $- = *e* ]]; SAVED_OPT_E=$?
    set +e
}

function throw()
{
    exit $1
}

function catch()
{
    export ex_code=$?
    (( $SAVED_OPT_E )) && set +e
    return $ex_code
}

function throwErrors()
{
    set -e
}

function ignoreErrors()
{
    set +e
}
################################################################################
# End - Functions to support try/catch exceptions
################################################################################


################################################################################
# Common Functions
################################################################################

comment()
{
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "- $1"
    echo "-------------------------------------------------------------------------------"
}

run_command()
{
    cmd="$1"
    raise_error=${2:-1}
    echo ">>> Running cmd:"
    echo "      $cmd"
    echo ""
    try
    (
        if [ $DRYRUN -eq 1 ] ;then
            echo "dryrun -- skip"
        else
            eval exec "$cmd"
        fi

        echo ""
    )
    catch || {
        case $ex_code in
            *)
                echo "Command: \"$cmd\" exited with error code: $ex_code"
                echo ""
                if [ $raise_error -eq 1 ] ;then
		            if echo "$cmd" | grep -q "schema"; then
			            echo "EPEL Repository must be enabled before executing ./setup.sh;You can enable it by installing the epel-release-latest package with command:"
			            echo "sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
			            echo "or seek assistance from your system administrator."
		            fi
                    throw $ex_code
                fi
                ;;
        esac
    }
}

yum_isinstalled()
{
  if sudo yum list installed "$@" >/dev/null 2>&1; then
    true
  else
    false
  fi
}

run_yum_command()
{
    operation=$1
    cmd=$2
    yum_cmd="sudo -E yum -y $operation $cmd"
    run_command "$yum_cmd"
}

do_yum_remove()
{
    if yum_isinstalled "$1"; then
        echo "$1 installed, removing it"
        run_yum_command "remove" "$1"
    fi
}

do_yum_install()
{
    run_yum_command "--setopt=skip_missing_names_on_install=False install" "$1"
}

do_yum_install_nogpgcheck()
{
    run_yum_command "--setopt=skip_missing_names_on_install=False install --nogpgcheck" "$1"
}

do_yum_install_with_remove()
{
    pkg="${1%.*}"
    pkg=$(echo $pkg | sed -e s/-$OPAE_VER//)
    do_yum_remove $pkg
    do_yum_install_nogpgcheck "$1"
}

################################################################################
# End - Common Functions
################################################################################

################################################################################
# OPAE RPM Install Function
################################################################################
install_prerequisite_package_for_centos()
{
    ################################################################################
    # Install the Extra Packages for Enterprise Linux (EPEL):
    # $ sudo yum install epel-release
    ################################################################################
	# User will manually run this step
    #comment "Install the Extra Packages for Enterprise Linux (EPEL)"
    #yum_install="epel-release"
    #do_yum_install "$yum_install"

    ################################################################################
    # Before you can install and build the OPAE software, you must install the required
    # packages by running the following command:
    # $ sudo yum install gcc gcc-c++ \
    #    cmake make autoconf automake libxml2 \
    #    libxml2-devel json-c-devel boost ncurses ncurses-devel \
    #    ncurses-libs boost-devel libuuid libuuid-devel python2-jsonschema \
    #    doxygen rsync hwloc-devel
    # Note: Some packages may already be installed. This command only installs the packages
    # that are missing.
    ################################################################################
    comment "Install Pre-requisite packages"
    yum_install="gcc gcc-c++ cmake make autoconf automake libxml2 libxml2-devel json-c-devel boost ncurses ncurses-devel ncurses-libs boost-devel libuuid libuuid-devel python2-jsonschema doxygen rsync hwloc-devel libpng12 python2-pip tbb-devel"
    do_yum_install "$yum_install"
	sudo -E pip install intelhex
}

install_prerequisite_package_for_ubuntu()
{
    comment "Install Pre-requisite packages"
    cmd="sudo -E apt-get install dkms libjson-c3 uuid-dev libjson-c-dev libhwloc-dev python-pip libjson-c-dev libhwloc-dev linux-headers-$(uname -r) libtbb-dev"
    run_command "$cmd"
    sudo -E pip install intelhex
}

install_opae_rpm_package_for_centos()
{
    comment "Installing OPAE rpm packages for RedHat/CentOS ..."
    ################################################################################
    #Remove any previous version of the OPAE FPGA driver by running the command:
    # sudo yum remove opae-intel-fpga-drv.x86_64.
    ################################################################################
    comment "Remove any previous version of the OPAE FPGA driver"
    yum_install="opae-intel-fpga-drv.x86_64"
    do_yum_remove "$yum_install"

    yum_install="opae-intel-fpga-driver.x86_64"
    do_yum_remove "$yum_install"

    ################################################################################
    #Remove any previous version of the OPAE FPGA libraries by running the commands:
    # sudo yum remove opae-ase.x86_64
    # sudo yum remove opae-tools.x86_64
    # sudo yum remove opae-tools-extra.x86_64
    # sudo yum remove opae-devel.x86_64
    # sudo yum remove opae-libs.x86_64
    # sudo yum remove opae.admin.noarch
    # sudo yum remove opae-one-time-update.noarch
    # sudo yum remove opae-super-rsu.noarch
    ################################################################################
    comment "Remove any previous version of the OPAE FPGA libraries"
    yum_install="opae-ase.x86_64"
    do_yum_remove "$yum_install"

    yum_install="opae-tools.x86_64"
    do_yum_remove "$yum_install"

    yum_install="opae-tools-extra.x86_64"
    do_yum_remove "$yum_install"

    yum_install="opae-devel.x86_64"
    do_yum_remove "$yum_install"

    yum_install="opae-libs.x86_64"
    do_yum_remove "$yum_install"

    yum_install="opae.admin.noarch"
    do_yum_remove "$yum_install"

    yum_install="opae-one-time-update.noarch"
    do_yum_remove "$yum_install"

    yum_install="opae-super-rsu.noarch"
    do_yum_remove "$yum_install"

    ################################################################################
    #Install the Intel® FPGA kernel drivers:
    # $ cd $DCP_LOC/sw
    # $ sudo yum install $DCP_LOC/sw/opae-intel-fpga-driver-${DRIVER_VER}.x86_64.rpm
    ################################################################################
    cd $DCP_LOC/sw
    comment "Update kernel source"
    sudo yum install kernel-devel-`uname -r`

    comment "Update kernel headers"
    sudo yum install kernel-headers-`uname -r`

    comment "Install the Intel® FPGA kernel drivers"
    yum_install="opae-intel-fpga-driver-${DRIVER_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"

    ################################################################################
    #Check the Linux kernel installation:
    # lsmod | grep fpga
    #    Sample output:
    #    intel_fpga_fme         51462  0
    #    intel_fpga_afu         31735  0
    #    fpga_mgr_mod           14693  1 intel_fpga_fme
    #    intel_fpga_pci         25804  2 intel_fpga_afu,intel_fpga_fme
    ################################################################################
    comment "Check the Linux kernel installation"
    lsmod_cmd="lsmod | grep fpga"
    run_command "$lsmod_cmd" 0

    ################################################################################
    #Install the OPAE Software
    ################################################################################
    comment "Installing OPAE software ..."

    ################################################################################
    #Complete the following steps to install the OPAE software:
    # 1. Install shared libraries at location /usr/lib, required for user applications to link against:
    #    sudo yum install opae-libs-${OPAE_VER}.x86_64.rpm
    # 2. Install the OPAE header at location /usr/include:
    #    sudo yum install opae-devel-${OPAE_VER}.x86_64.rpm
    # 3. Install the OPAE provided tools at location /usr/bin (For example: fpgaconf and fpgainfo):
    #    sudo yum install opae-tools-${OPAE_VER}.x86_64.rpm
    #    sudo yum install opae-tools-extra-${OPAE_VER}.x86_64.rpm
    #    For more information about tools, refer to the OPAE tools document.
    # 4. Install the ASE related shared libraries at location /usr/lib:
    #    sudo yum install opae-ase-${OPAE_VER}.x86_64.rpm
    # 5. Run ldconfig
    #    sudo ldconfig
    ################################################################################
    comment "1. Install shared libraries at location /usr/lib, required for user applications to link against"
    yum_install="opae-libs-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"

    comment "2. Install the OPAE header at location /usr/include"
    yum_install="opae-devel-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"

    comment "3. Install the OPAE provided tools at location /usr/bin"
    yum_install="opae-tools-extra-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"
    echo ""
    yum_install="opae-tools-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"

    comment "4. Install the ASE related shared libraries at location /usr/lib"
    yum_install="opae-ase-${OPAE_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"

    comment "5. Install the opae.admin library"
    yum_install="opae.admin-${ADMIN_VER}.noarch.rpm"
    do_yum_install_with_remove "$yum_install"

    comment "6. Install the one-time-update"
    yum_install="opae-one-time-update-a10-gx-pac-${OTSU_VER}.noarch.rpm"
    do_yum_install_with_remove "$yum_install"

    comment "7. Install the super-rsu library"
    yum_install="opae-super-rsu-a10-gx-pac-${SUPER_RSU_VER}.noarch.rpm"
    do_yum_install_with_remove "$yum_install"

    comment "9. sudo ldconfig"
    cmd="sudo ldconfig"
    run_command "$cmd" 0
}

install_opae_rpm_package_for_ubuntu()
{
    comment "Installing OPAE deb packages for Ubuntu ..."
    comment "Check opae libraries installed"
    ls_opae_libs_cmd="sudo dpkg -l | grep opae"
    run_command "$ls_opae_libs_cmd" 0

    #1)	To remove any ubuntu deb packages installed
    comment "Remove any previous version of the OPAE FPGA libraries"
    cmd="sudo dpkg -r opae-intel-fpga-driver"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-ase"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-tools-extra"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-tools"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-devel"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-libs"
    run_command "$cmd"

    cmd="sudo dpkg -r python-opae.admin"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-a10-gx-pac-fpgaotsu-base"
    run_command "$cmd"

    cmd="sudo dpkg -r opae-a10-gx-pac-super-rsu-base"
    run_command "$cmd"

    comment "Check opae libraries installed"
    run_command "$ls_opae_libs_cmd" 0

    ################################################################################
    #Install the Intel® FPGA kernel drivers:
    # $ cd $DCP_LOC/sw
    # $ sudo apt-get install ./opae-intel-fpga-driver-${DRIVER_VER}.x86_64.deb
    ################################################################################
    cd $DCP_LOC/sw

    #2)	Install OPAE Intel® FPGA kernel drivers
    comment "Install the Intel® FPGA kernel drivers"
    cmd="sudo apt-get install ./opae-intel-fpga-driver_2.0.3_all.deb"
    run_command "$cmd"

    #3)	 Install OPAE Libraries
    comment "1. Ubuntu installing OPAE software ..."
    cmd="sudo apt-get install ./opae-libs-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    comment "2. Ubuntu Install the OPAE header"
    cmd="sudo apt-get install ./opae-devel-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    comment "3. Ubuntu install the OPAE provided tools"
    cmd="sudo apt-get install ./opae-tools-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    cmd="sudo apt-get install ./opae-tools-extra-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    comment "4. Ubuntu install the ASE related shared libraries"
    cmd="sudo apt-get install ./opae-ase-${OPAE_VER}.x86_64.deb"
    run_command "$cmd"

    comment "5. Ubuntu Install the opae.admin library"
    cmd="sudo apt-get install ./python-opae.admin_1.0.2_all.deb"
    run_command "$cmd"

    comment "6. Ubuntu Install the one-time-update"
    cmd="sudo apt-get install ./opae-a10-gx-pac-fpgaotsu-base_1.2.1_all.deb"
    run_command "$cmd"

    comment "7. Ubuntu Install the super-rsu library"
    cmd="sudo apt-get install ./opae-a10-gx-pac-super-rsu-base_1.2.1_all.deb"
    run_command "$cmd"
}

install_opae_pacsign_package_for_centos()
{
    comment "Installing OPAE PACSign package for RedHat/CentOS ..."
    ################################################################################
    # Remove any previous version of the OPAE PACSign by running the commands:
    # sudo yum remove opae.pac_sign.x86_64.rpm
    ################################################################################
    yum_install="opae.pac_sign.x86_64"
    do_yum_remove "$yum_install"

    ################################################################################
    #Install the OPAE PACSign
    ################################################################################
    cd $DCP_LOC/sw
    comment "Installing OPAE PACSign ..."
    yum_install="opae.pac_sign-${PACSIGN_VER}.x86_64.rpm"
    do_yum_install_with_remove "$yum_install"

}

install_opae_pacsign_package_for_ubuntu()
{
    comment "Installing OPAE PACSign deb packages for Ubuntu ..."
    cd $DCP_LOC/sw

    #	Remove any ubuntu PACSign deb packages installed
    cmd="sudo dpkg -r python3-opae.pac-sign"
    run_command "$cmd"

    cmd="sudo apt-get install ./python3-opae.pac-sign_${PACSIGN_VER}_amd64.deb"
    run_command "$cmd"
}

install_quartus_dev_package()
{
    comment "Installing the Intel® Quartus® Prime Pro Edition Software to ${QUARTUS_INSTALLDIR}"
    echo ${QUARTUS_DEFAULT_INSTALLDIR}
    echo ${QUARTUS_INSTALLER}
    echo ${QUARTUS_UPDATE}
    echo ${AOCL_INSTALLER}
    QINSTALLDIR="$QUARTUS_INSTALLDIR"

    installer="$SCRIPT_PATH/$QUARTUS_INSTALLER"
    install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --disable-components quartus_update --accept_eula 1"
    install_cmd="$installer $install_arg"
    run_command "${sudo_qcmd} ${install_cmd}"

    if [ $QUARTUS_UPDATE ] ;then
        comment "Installing the Intel® Quartus® Prime Pro Edition Software Update"
        installer="$SCRIPT_PATH/$QUARTUS_UPDATE"
        install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --skip_registration 1"
        install_cmd="$installer $install_arg"
        run_command "${sudo_qcmd} ${install_cmd}"
    fi

    ## loop through the array of patches
    for p in "${patches[@]}"
    do
        echo "Installing quartus-${QUARTUS_VERSION}-${p}-linux.run"
        installer="$SCRIPT_PATH/quartus-${QUARTUS_VERSION}-${p}-linux.run"
        install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --accept_eula 1 --skip_registration 1"
        install_cmd="$installer $install_arg"
        run_command "${sudo_qcmd} ${install_cmd}"
    done

    echo "Installing ${AOCL_INSTALLER}"
    installer="$SCRIPT_PATH/$AOCL_INSTALLER"
    install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --accept_eula 1"
    install_cmd="$installer $install_arg"
    run_command "${sudo_qcmd} ${install_cmd}"
}


install_quartus_rte_package()
{
    comment "Installing the Intel® FPGA RTE for OpenCL to ${QUARTUS_INSTALLDIR}"
    echo ${QUARTUS_DEFAULT_INSTALLDIR}
    echo ${QUARTUS_INSTALLER}
    echo ${QUARTUS_UPDATE}
    echo ${AOCL_INSTALLER}
    QINSTALLDIR="$QUARTUS_INSTALLDIR"

    installer="$SCRIPT_PATH/$AOCL_INSTALLER"
    install_arg="--mode unattended --installdir \"$QINSTALLDIR\" --accept_eula 1 --skip_registration 1"
    install_cmd="$installer $install_arg"
    run_command "${sudo_qcmd} ${install_cmd}"
}


################################################################################
# Main script starts
################################################################################

comment "Begin installing $PRODUCT_NAME"

# Check if we are running on a supported version of Linux distribution
# Both RedHat and CentOS have the /etc/redhat-release file.
unsupported_os=1
unsupported_kernel=1
is_ubuntu=0
os_file="/etc/redhat-release"

# check for RedHat/CentOS
if [ -f $os_file ] ;then

	os_version=`cat $os_file | grep release | sed -e 's/ (.*//g'`
	os_platform=`echo ${os_version} | grep "Red Hat Enterprise" || echo ${os_version} | grep "CentOS"`

	if [ "$os_platform" != "" ] ;then
        os_rev=`echo ${os_platform} | awk -F "release " '{print $2}' | sed -e 's/ .*//g'`
        if [[ ${os_rev} = ${SUPPORTED_CENTOS_VERSION}* ]]; then
            unsupported_os=0
        fi
	fi
fi

kernel_ver=`uname -r`
if [[ ${kernel_ver} = ${SUPPORTED_CENTOS_KERNEL_VERSION}* ]] ;then
    unsupported_kernel=0
fi

if [[ $unsupported_os -eq 1 ]] ;then
  # check for Ubuntu
  os_file="/etc/issue"

  if [ -f $os_file ] ;then
	os_platform=`cat ${os_file} | grep "Ubuntu"`

	if [ "$os_platform" != "" ] ;then
        os_rev=`echo ${os_platform} | awk -F "Ubuntu " '{print $2}' | sed -e 's/ .*//g'`
        os_version=`head -n 1 $os_file`

        if [[ ${os_rev} = ${SUPPORTED_UBUNTU_VERSION}* ]]; then
            unsupported_os=0
            unsupported_kernel=0
            is_ubuntu=1
        fi
	fi
  fi
fi


DEFAULT="y"

if [[ $unsupported_os -eq 1 ]] || [[ $unsupported_kernel -eq 1 ]] ;then
	echo ""
	echo "$PRODUCT_NAME is only supported on RedHat ${SUPPORTED_CENTOS_VERSION}.* kernel ${SUPPORTED_CENTOS_KERNEL_VERSION}.* or Ubuntu ${SUPPORTED_UBUNTU_VERSION},"
	echo "you're currently on ${os_version} using kernel ${kernel_ver}."
	echo "Refer to the $PRODUCT_NAME Quick Start Guide,"
	echo "    https://www.intel.com/content/www/us/en/programmable/documentation/iyu1522005567196.html,"
	echo "for complete operating system support information."
	echo ""

	answer="n"
    if [ $YESTOALL -eq 1 ] ;then
	    answer="y"
    fi

	while [ "$answer" != "y" ]
	do
        read -e -p "Do you want to continue to install the software? (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"

		if [ "$answer" = "n" ] ;then
			exit
		fi
	done
fi

if [ `uname -m` != "x86_64" ] ;then
	echo ""
	echo "The Intel software you are installing is 64-bit software and will not work on the 32-bit platform on which it is being installed."
	echo ""

	answer="n"
    if [ $YESTOALL -eq 1 ] ;then
	    answer="y"
    fi

	while [ "$answer" != "y" ]
	do
        read -e -p "Do you want to continue to install the software? (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"

		if [ "$answer" = "n" ] ;then
			exit
		fi
	done
fi

if [ $prompt_opae -eq 1 ] ;then

	answer="n"
    if [ $YESTOALL -eq 1 ] ;then
	    answer="y"
    fi

	while [ "$answer" != "y" ]
	do
        echo ""
        read -e -p "Do you wish to install OPAE? Note: Installing will require administrative access (sudo) and network access. (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"

		if [ "$answer" = "n" ] ;then
            install_opae=0
            echo ""
            echo "*** Note: You can install OPAE software package manually by following the Quick Start Guide section: Installing the OPAE Software Package."
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            echo ""
			break
		fi
	done
fi

if [ $prompt_pacsign -eq 1 ] ;then

	answer="n"
    if [ $YESTOALL -eq 1 ] ;then
	    answer="y"
    fi

	while [ "$answer" != "y" ]
	do
        echo ""
        read -e -p "Do you wish to install the OPAE PACSign package? Note: Installing will require administrative access (sudo) and network access. (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"

		if [ "$answer" = "n" ] ;then
            install_pacsign=0
            echo ""
            echo "*** Note: You can install OPAE PACSign package manually by following the Quick Start Guide section: Installing the OPAE PACSign Package."
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            echo ""
			break
		fi
	done
fi

# get script path
SCRIPT_PATH=`dirname "$0"`
if test "$SCRIPT_PATH" = "." -o -z "$SCRIPT_PATH" ; then
	SCRIPT_PATH=`pwd`
fi
SCRIPT_PATH="$SCRIPT_PATH/components"

################################################################################
# show license agreement
################################################################################
more "$SCRIPT_PATH/../licenses/COMMERCIAL_USE_SOFTWARE_LICENSE_AGREEMENT_RC_1_2_1_wBW.txt"

	answer="n"

	while [ "$answer" != "y" ]
	do
        read -e -p "Do you accept this license? (Y/n): " answer
        answer="${answer:-${DEFAULT}}"
        answer="${answer,,}"

		if [ "$answer" = "n" ] ;then
			exit
		fi
	done

################################################################################
# checking validation of INSTALLDIR
################################################################################
is_valid=0              # flag to capture valid install path is selected
stack_select_flag=1     # flag to capture whether user selects diff install path
w_installs=0            # flag to run stack install as sudo. sets to 1 only if w_root=0 && w_stack=0
w_stack=1               # flag whether script can write to install path
w_root=0                # flag whether script can write to root paths (ie /)

if [[ "$INSTALLDIR" = "" ]] && [ $YESTOALL -eq 1 ] ;then
    INSTALLDIR="$DEFAULT_INSTALLDIR"
    is_valid=1
fi

while [ $is_valid -eq 0 ]
do
    # prompt user to provide directory where to extract the stack
    if [ "$INSTALLDIR" = "" ] ;then
        INSTALLDIR="$DEFAULT_INSTALLDIR"

        answer=""
        echo ""
        echo -n "Enter the path you want to extract the Intel® Acceleration Stack for Intel® Xeon® CPU with FPGAs release package [default: $INSTALLDIR]: "
	    read answer

	    if [ "$answer" != "" ] ;then
            INSTALLDIR=$answer
        fi
    fi
    # confirm whether user has write permissiosn to target install path
    stack_basedir=$INSTALLDIR
    while [ ! -e $stack_basedir ]
    do
        stack_basedir=$(dirname $stack_basedir)
    done

    if [ ! -w $stack_basedir ] ;then
        to_continue="n"
        w_stack=0
        if [ $YESTOALL -eq 1 ] ;then
            to_continue="y"
        fi

        while [ "to_continue" != "y" ]
        do
            echo ""
            echo "Warning: Elevated permissions are required in order to write to directory $stack_basedir"
            read -e -p "Do you want to proceed? (Choosing 'n' will allow you to select a different installation directory (Y/n)" to_continue
            echo ""
            to_continue="${to_continue:-${DEFAULT}}"
            to_continue="${to_continue,,}"

            if [ "$to_continue" = "y" ] ;then
                stack_select_flag=1
                break
            fi

            if [ "$to_continue" = "n" ] ;then
                stack_select_flag=0
                INSTALLDIR=""
                w_stack=1
                break
            fi
        done

    fi

    if [ "$stack_select_flag" -eq 1 ] ;then
        # notify user that input install dir is a file, try again
        if [ -f "$INSTALLDIR" ] ;then
    	    echo "Error: $INSTALLDIR already exists as a file, you need to specify a directory path."
            INSTALLDIR=""
            YESTOALL=0
        else
            if [ -d "$INSTALLDIR" ] ;then
    	        to_continue="n"
                if [ $YESTOALL -eq 1 ] ;then
    	            to_continue="y"
                    is_valid=1
                fi

    	        while [ "$to_continue" != "y" ]
    	        do
                    read -e -p "Directory $INSTALLDIR already exists, do you want to continue to install to this location? (Choosing 'y' will remove all the existing files there) (Y/n): " to_continue
                    to_continue="${to_continue:-${DEFAULT}}"
                    to_continue="${to_continue,,}"

    		        if [ "$to_continue" = "y" ] ;then
                        is_valid=1
                        break
    		        fi
    		        if [ "$to_continue" = "n" ] ;then
                        INSTALLDIR=""
                        break
    		        fi
    	        done
            else
                is_valid=1
            fi
        fi
    fi
done

#remove the trailing slash
INSTALLDIR="${INSTALLDIR%/}"

#add PRODUCT_DIR to INSTALLDIR if it is not there
if [[ "${INSTALLDIR}" != *"$PRODUCT_DIR"* ]] ;then
    INSTALLDIR="${INSTALLDIR}/$PRODUCT_DIR"
fi

if [ "$DCP_LOC" = "" ] ;then
    DCP_LOC="${INSTALLDIR}"
fi

# confirm whether sudo is needed to remove existing INSTALLDIR
if [ -w / ] ;then
    w_root=1
fi
if [ "$w_root" -eq 0 ] && [ "$w_stack" -eq 0 ] ;then
    w_installs=1
fi
if [ "$w_installs" -eq 1 ] ;then
    sudo_scmd="sudo"
else
    sudo_scmd=""
fi

# confirm whether sudo is needed to create new INSTALLDIR
base_installdir=$(dirname $INSTALLDIR)

if [ ! -d "${base_installdir}" ]; then
    echo "${base_installdir} doesn't exist yet, will try to create."
    if mkdir -p "${base_installdir}" ; then
        echo "Successfully created directory"
    else
        echo "Failed to create, perhaps permission issues"
    fi
fi

if [ ! -w "$base_installdir" ] && [ "$w_root" -eq 0 ] ;then
    sudo_pscmd="sudo"
else
    sudo_pscmd=""
fi

echo ""
echo INSTALLDIR="${INSTALLDIR}"
# install the prerequisite packages first to see if user has sudo permission
if [ $install_opae -eq 1 ] ;then
    if [ $is_ubuntu -eq 1 ] ;then
        install_prerequisite_package_for_ubuntu
    else
        install_prerequisite_package_for_centos
    fi
fi

################################################################################
# unzip the DCP installer
################################################################################
if [ -d "$INSTALLDIR" ] ;then
    echo ""
    echo "Removing ${INSTALLDIR} ..."
    eval "$sudo_scmd chmod -R +w "$INSTALLDIR""
    eval "$sudo_scmd rm -rf "$INSTALLDIR""
fi
if [ ! -d "$INSTALLDIR" ] ;then
    eval "$sudo_pscmd mkdir -p "$INSTALLDIR""
fi

comment "Copying $DCP_INSTALLER to $INSTALLDIR"
cp_cmd="$sudo_pscmd cp -pf $SCRIPT_PATH/$DCP_INSTALLER $INSTALLDIR"
run_command "$cp_cmd"

if [ "$DCP_LOC" != "" ] ;then

    #remove the trailing slash
    DCP_LOC="${DCP_LOC%/}"

    #always add package name to the path
    DCP_LOC="${DCP_LOC}/${DCP_INSTALLER/.*/}"

    if [ -d "$DCP_LOC" ] ;then
       eval "$sudo_pscmd rm -rf "$DCP_LOC""
    fi

    eval "$sudo_pscmd mkdir -p "$DCP_LOC""
    cd $DCP_LOC

    comment "Untar $DCP_INSTALLER"
    echo DCP_LOC="${DCP_LOC}"
    untar_cmd="$sudo_pscmd tar -xzf $SCRIPT_PATH/$DCP_INSTALLER --no-same-owner"
    run_command "$untar_cmd"

    untar_cmd="$sudo_pscmd tar xf ${DCP_LOC}/opencl/opencl_bsp*.tar.gz -C ${DCP_LOC}/opencl/ --no-same-owner"
    run_command "$untar_cmd"

    comment "Copying afu_platform_info tool to $DCP_LOC/sw"
    cp_cmd="$sudo_pscmd cp -pf $SCRIPT_PATH/afu_platform_info $DCP_LOC/sw"
    run_command "$cp_cmd"
fi

################################################################################
#Installing the OPAE RPM packages
################################################################################
if [ $install_opae -eq 1 ] ;then
    if [ $is_ubuntu -eq 1 ] ;then
        install_opae_rpm_package_for_ubuntu
    else
        install_opae_rpm_package_for_centos
    fi
fi

################################################################################
#Installing the OPAE PACSign package
################################################################################
if [ $install_pacsign -eq 1 ] ;then
    if [ $is_ubuntu -eq 1 ] ;then
        install_opae_pacsign_package_for_ubuntu
    else
        install_opae_pacsign_package_for_centos
    fi
fi

################################################################################
# checking validation of QUARTUS_INSTALLDIR
################################################################################
# default flag defintions for quartus installation
is_quartus_installdir_valid=0   # flag to capture valid install path is selected
quartus_select_flag=1           # flag to capture whether user selects diff install path
w_installq=0                    # flag to run install as sudo. sets to 1 only if w_root=0 && w_quartus=0
w_quartus=1                     # flag whether script can write to install path

if [[ "$QUARTUS_INSTALLDIR" = "" ]] && [ $YESTOALL -eq 1 ] ;then
    QUARTUS_INSTALLDIR="$QUARTUS_DEFAULT_INSTALLDIR"
    is_quartus_installdir_valid=1
fi

while [ $is_quartus_installdir_valid -eq 0 ]
do
    # prompt user to provide directory to install opencl/quartus
    if [ "$QUARTUS_INSTALLDIR" = "" ] ;then
        QUARTUS_INSTALLDIR="$QUARTUS_DEFAULT_INSTALLDIR"

        answer=""
        echo ""
        echo -n "Enter the path you want to extract the Intel® FPGA RTE for OpenCL software release package [default: $QUARTUS_INSTALLDIR]: "
	    read answer

	    if [ "$answer" != "" ] ;then
            QUARTUS_INSTALLDIR=$answer
        fi
    fi

    # confirm whether user has write permissions to target install path
    quartus_basedir=$QUARTUS_INSTALLDIR
    while [ ! -e $quartus_basedir ]
    do
        quartus_basedir=$(dirname $quartus_basedir)
    done

    if [ ! -w $quartus_basedir ] ;then
        to_continue="n"
        w_quartus=0
        if [ $YESTOALL -eq 1 ] ;then
            to_continue="y"
        fi

        while [ "to_continue" != "y" ]
        do
            echo ""
            echo "Warning: Elevated permissions are required in order to write to directory $quartus_basedir"
            read -e -p "Do you want to proceed? (Choosing 'n' will allow you to select a different installation directory) (Y/n)" to_continue
            echo ""
            to_continue="${to_continue:-${DEFAULT}}"
            to_continue="${to_continue,,}"

    		if [ "$to_continue" = "y" ] ;then
                quartus_select_flag=1
                break
    		fi
    		if [ "$to_continue" = "n" ] ;then
                quartus_select_flag=0
                QUARTUS_INSTALLDIR=""
                w_quartus=1
                break
    		fi
        done
    fi

    if [ "$quartus_select_flag" -eq 1 ] ;then
        # notify user that input install dir is a file, try again
        if [ -f "$QUARTUS_INSTALLDIR" ] ;then
    	    echo "Error: $QUARTUS_INSTALLDIR already exists as a file, you need to specify a directory path."
            QUARTUS_INSTALLDIR=""
            YESTOALL=0

        # prompt user to overwrite existing directory in target install path
        else
            if [ -d "$QUARTUS_INSTALLDIR" ] ;then
    	        to_continue="n"
                if [ $YESTOALL -eq 1 ] ;then
    	            to_continue="y"
                    is_quartus_installdir_valid=1
                fi

    	        while [ "$to_continue" != "y" ]
    	        do
                    read -e -p "Directory $QUARTUS_INSTALLDIR already exists, do you want to continue to install to this location? (Choosing 'y' will remove all the existing files there) (Y/n): " to_continue
                    to_continue="${to_continue:-${DEFAULT}}"
                    to_continue="${to_continue,,}"

    		        if [ "$to_continue" = "y" ] ;then
                        is_quartus_installdir_valid=1
                        break
    		        fi
    		        if [ "$to_continue" = "n" ] ;then
                        QUARTUS_INSTALLDIR=""
                        break
    		        fi
    	        done
            else
                is_quartus_installdir_valid=1
            fi
        fi
    fi
done

#remove the trailing slash
QUARTUS_INSTALLDIR="${QUARTUS_INSTALLDIR%/}"

echo ""
echo QUARTUS_INSTALLDIR="${QUARTUS_INSTALLDIR}"

# confirm whether sudo is needed for openl/quartus commands
if [ "$w_root" -eq 0 ] && [ "$w_quartus" -eq 0 ] ;then
    w_installq=1
fi
if [ "$w_installq" -eq 1 ] ;then
    sudo_qcmd="sudo"
else
    sudo_qcmd=""
fi

# remove old opencl/quartus directory (if applicable)
if [ -d "$QUARTUS_INSTALLDIR" ] ;then
    echo ""
    echo "Removing ${QUARTUS_INSTALLDIR} ..."
    eval "$sudo_qcmd chmod -R +w "$QUARTUS_INSTALLDIR""
    eval "$sudo_qcmd rm -rf "$QUARTUS_INSTALLDIR""
fi

################################################################################
#Installing the Intel® Quartus® Prime Pro Edition Software
################################################################################
if [ "$PKG_TYPE" = "dev" ] ;then
    install_quartus_dev_package
else
    install_quartus_rte_package
fi

################################################################################
#    Create env.sh to be sourced to setup the the environment
################################################################################

QENV_TMP="$SCRIPT_PATH/init_env.sh"
QENV="$INSTALLDIR/init_env.sh"
comment "Creating ${QENV_TMP}"

echo "" > "${QENV_TMP}"
echo "echo export ${qproduct_env}=\"${QINSTALLDIR}/${qproduct}\"" >> "${QENV_TMP}"
echo "export ${qproduct_env}=\"${QINSTALLDIR}/${qproduct}\"" >> "${QENV_TMP}"
echo "" >> "${QENV_TMP}"

if [ "$DCP_LOC" != "" ] ;then
    echo "echo export OPAE_PLATFORM_ROOT=\"${DCP_LOC}\"" >> "${QENV_TMP}"
    echo "export OPAE_PLATFORM_ROOT=\"${DCP_LOC}\"" >> "${QENV_TMP}"
    echo "" >> "${QENV_TMP}"

    echo "echo export AOCL_BOARD_PACKAGE_ROOT=\"${DCP_LOC}/opencl/opencl_bsp\"" >> "${QENV_TMP}"
    echo "export AOCL_BOARD_PACKAGE_ROOT=\"${DCP_LOC}/opencl/opencl_bsp\"" >> "${QENV_TMP}"
    if [ $install_opae -eq 1 ] ; then
	echo "if ls /dev/intel-fpga-* 1> /dev/null 2>&1; then" >> "${QENV_TMP}"
        echo "echo source \$AOCL_BOARD_PACKAGE_ROOT/linux64/libexec/setup_permissions.sh" >> "${QENV_TMP}"
        echo "source \$AOCL_BOARD_PACKAGE_ROOT/linux64/libexec/setup_permissions.sh >> /dev/null " >> "${QENV_TMP}"
	echo "fi" >> "${QENV_TMP}"
    fi
    OPAE_PLATFORM_BIN="${DCP_LOC}/bin"
    echo "OPAE_PLATFORM_BIN=\"${OPAE_PLATFORM_BIN}\"" >> "${QENV_TMP}"
    echo "if [[ \":\${PATH}:\" = *\":\${OPAE_PLATFORM_BIN}:\"* ]] ;then" >> "${QENV_TMP}"
    echo "    echo \"\\\$OPAE_PLATFORM_ROOT/bin is in PATH already\"" >> "${QENV_TMP}"
    echo "else" >> "${QENV_TMP}"
    echo "    echo \"Adding \\\$OPAE_PLATFORM_ROOT/bin to PATH\"" >> "${QENV_TMP}"
    echo "    export PATH=\"\${PATH}\":\"\${OPAE_PLATFORM_BIN}\"" >> "${QENV_TMP}"
    echo "fi"  >> "${QENV_TMP}"
    echo "echo sudo cp \"${DCP_LOC}/sw/afu_platform_info\" /usr/bin/" >> "${QENV_TMP}"
    echo "sudo cp \"${DCP_LOC}/sw/afu_platform_info\" /usr/bin/" >> "${QENV_TMP}"
    echo "sudo chmod 755 /usr/bin/afu_platform_info" >> "${QENV_TMP}"
    echo "" >> "${QENV_TMP}"
fi

if [ "$PKG_TYPE" = "dev" ] ;then
	echo "echo export ${opencl_dev_env}=\"${QINSTALLDIR}/${opencl}\"" >> "${QENV_TMP}"
	echo "export ${opencl_dev_env}=\"${QINSTALLDIR}/${opencl}\"" >> "${QENV_TMP}"
	echo "echo export ${opencl_alt_dev_env}=\$${opencl_dev_env}" >> "${QENV_TMP}"
	echo "export ${opencl_alt_dev_env}=\$${opencl_dev_env}" >> "${QENV_TMP}"
	echo "" >> "${QENV_TMP}"
	QUARTUS_BIN="${QINSTALLDIR}/${qproduct}/bin"
	echo "QUARTUS_BIN=\"${QUARTUS_BIN}\"" >> "${QENV_TMP}"
	echo "if [[ \":\${PATH}:\" = *\":\${QUARTUS_BIN}:\"* ]] ;then" >> "${QENV_TMP}"
	echo "    echo \"\\\$${qproduct_env}/bin is in PATH already\"" >> "${QENV_TMP}"
	echo "else" >> "${QENV_TMP}"
	echo "    echo \"Adding \\\$${qproduct_env}/bin to PATH\"" >> "${QENV_TMP}"
	echo "    export PATH=\"\${QUARTUS_BIN}\":\"\${PATH}\"" >> "${QENV_TMP}"
	echo "fi"  >> "${QENV_TMP}"
    	echo "echo source \$${opencl_dev_env}/init_opencl.sh" >> "${QENV_TMP}"
    	echo "source \$${opencl_dev_env}/init_opencl.sh >> /dev/null" >> "${QENV_TMP}"
	echo "" >> "${QENV_TMP}"
fi

if [ "$PKG_TYPE" = "rte" ] ;then
	echo "echo export ${opencl_alt_dev_env}=\$${qproduct_env}" >> "${QENV_TMP}"
	echo "export ${opencl_alt_dev_env}=\$${qproduct_env}" >> "${QENV_TMP}"
    	echo "echo source \$${qproduct_env}/init_opencl.sh" >> "${QENV_TMP}"
    	echo "source \$${qproduct_env}/init_opencl.sh >> /dev/null" >> "${QENV_TMP}"
fi
eval "$sudo_pscmd mv $QENV_TMP $QENV"
################################################################################
#    End of the installation
################################################################################
comment "Finished installing $PRODUCT_NAME"
echo ""
echo "*** Note: You need to source ${QENV} to set up your environment. ***"
echo ""
