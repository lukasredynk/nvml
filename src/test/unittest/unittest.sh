#
# Copyright (c) 2014, Intel Corporation
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in
#       the documentation and/or other materials provided with the
#       distribution.
#
#     * Neither the name of Intel Corporation nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

. ../testconfig.sh

# defaults
[ "$TEST" ] || export TEST=check
[ "$FS" ] || export FS=local
[ "$BUILD" ] || export BUILD=debug

# force globs to fail if they don't match
shopt -s failglob

#
# For non-static build testing, the variable TEST_LD_LIBRARY_PATH is
# constructed so the test pulls in the appropriate library from this
# source tree.  To override this behavior (i.e. to force the test to
# use the libraries installed elsewhere on the system), set
# TEST_LD_LIBRARY_PATH and this script will not override it.
#
# For example, in a test directory, run:
#	TEST_LD_LIBRARY_PATH=/usr/lib ./TEST0
#
[ "$TEST_LD_LIBRARY_PATH" ] || {
	case "$BUILD"
	in
	debug)
		TEST_LD_LIBRARY_PATH=../../debug
		;;
	nondebug)
		TEST_LD_LIBRARY_PATH=../../nondebug
		;;
	esac
}

#
# When running static binary tests, append the build type to the binary
#
case "$BUILD"
in
	static-*)
		EXESUFFIX=.$BUILD
		;;
esac

#
# The variable DIR is constructed so the test uses that directory when
# constructing test files.  DIR is chosen based on the fs-type for
# this test, and if the appropriate fs-type doesn't have a directory
# defined in testconfig.sh, the test is skipped.
#
# This behavior can be overridden by setting DIR.  For example:
#	DIR=/force/test/dir ./TEST0
#
[ "$DIR" ] || {
	case "$FS"
	in
	local)
		DIR=$LOCAL_FS_DIR
		;;
	pmem)
		DIR=$PMEM_FS_DIR
		;;
	non-pmem)
		DIR=$NON_PMEM_FS_DIR
		;;
	esac
	[ "$DIR" ] || {
		[ "$UNITTEST_QUIET" ] || echo "$UNITTEST_NAME: SKIP fs-type $FS (not configured)"
		exit 0
	}
}

#
# The default is to turn on library logging to level 3 and save it to local files.
# Tests that don't want it on, should override these environment variables.
#
export VMEM_LOG_LEVEL=3
export VMEM_LOG_FILE=vmem$UNITTEST_NUM.log
export PMEM_LOG_LEVEL=3
export PMEM_LOG_FILE=pmem$UNITTEST_NUM.log
export PMEMBLK_LOG_LEVEL=3
export PMEMBLK_LOG_FILE=pmemblk$UNITTEST_NUM.log
export PMEMLOG_LOG_LEVEL=3
export PMEMLOG_LOG_FILE=pmemlog$UNITTEST_NUM.log
export PMEMOBJ_LOG_LEVEL=3
export PMEMOBJ_LOG_FILE=pmemobj$UNITTEST_NUM.log

export VMMALLOC_POOL_DIR="$DIR"
export VMMALLOC_POOL_SIZE=$((16 * 1024 * 1024))
export VMMALLOC_LOG_LEVEL=3
export VMMALLOC_LOG_FILE=vmmalloc$UNITTEST_NUM.log

#
# create_file -- create zeroed out files of a given length in megs
#
# example, to create two files, each 1GB in size:
#	create_file 1024 testfile1 testfile2
#
function create_file() {
	size=$1
	shift
	for file in $*
	do
		dd if=/dev/zero of=$file bs=1M count=$size >> prep$UNITTEST_NUM.log
	done
}

#
# create_holey_file -- create holey files of a given length in megs
#
# example, to create two files, each 1GB in size:
#	create_holey_file 1024 testfile1 testfile2
#
function create_holey_file() {
	size=$1
	shift
	for file in $*
	do
		truncate -s ${size}M $file >> prep$UNITTEST_NUM.log
	done
}

#
# expect_normal_exit -- run a given command, expect it to exit 0
#
function expect_normal_exit() {
	eval $ECHO LD_LIBRARY_PATH=$TEST_LD_LIBRARY_PATH \
	$TRACE $*
}

#
# expect_abnormal_exit -- run a given command, expect it to exit non-zero
#
function expect_abnormal_exit() {
	set +e
	eval $ECHO LD_LIBRARY_PATH=$TEST_LD_LIBRARY_PATH \
	$TRACE $*
	set -e
}

#
# require_unlimited_vm -- require unlimited virtual memory
#
# This implies requirements for:
# - overcommit_memory enabled (/proc/sys/vm/overcommit_memory is 0 or 1)
# - unlimited virtual memory (ulimit -v is unlimited)
#
function require_unlimited_vm() {
	local overcommit=$(cat /proc/sys/vm/overcommit_memory)
	local vm_limit=$(ulimit -v)
	[ "$overcommit" != "2" ] && [ "$vm_limit" = "unlimited" ] && return
	echo "$UNITTEST_NAME: SKIP required: overcommit_memory enabled and unlimited virtual memory"
	exit 0
}

#
# require_no_superuser -- require user without superuser rights
#
function require_no_superuser() {
	local user_id=$(id -u)
	[ "$user_id" != "0" ] && return
	echo "$UNITTEST_NAME: SKIP required: run without superuser rights"
	exit 0
}

#
# require_test_type -- only allow script to continue for a certain test type
#
function require_test_type() {
	for type in $*
	do
		[ "$type" = "$TEST" ] && return
	done
	[ "$UNITTEST_QUIET" ] || echo "$UNITTEST_NAME: SKIP test-type $TEST ($* required)"
	exit 0
}

#
# require_fs_type -- only allow script to continue for a certain fs type
#
function require_fs_type() {
	for type in $*
	do
		[ "$type" = "$FS" ] && return
	done
	[ "$UNITTEST_QUIET" ] || echo "$UNITTEST_NAME: SKIP fs-type $FS ($* required)"
	exit 0
}

#
# require_build_type -- only allow script to continue for a certain build type
#
function require_build_type() {
	for type in $*
	do
		[ "$type" = "$BUILD" ] && return
	done
	[ "$UNITTEST_QUIET" ] || echo "$UNITTEST_NAME: SKIP build-type $BUILD ($* required)"
	exit 0
}

#
# setup -- print message that test setup is commencing
#
function setup() {
	echo "$UNITTEST_NAME: SETUP ($TEST/$FS/$BUILD)"
}

#
# check -- check test results (using .match files)
#
function check() {
	../match $(find . -regex "[^0-9]*${UNITTEST_NUM}\.log\.match" | xargs)
}

#
# pass -- print message that the test has passed
#
function pass() {
	echo $UNITTEST_NAME: PASS
}

# Paths to some useful tools
[ -n "$PMEMPOOL" ] || PMEMPOOL=../../tools/pmempool/pmempool
[ -n "$PMEMSPOIL" ] || PMEMSPOIL=../pmemspoil/pmemspoil
[ -n "$PMEMWRITE" ] || PMEMWRITE=../pmemwrite/pmemwrite

# Length of pool file's signature
SIG_LEN=8

# Length of arena's signature
ARENA_SIG_LEN=16

# Signature of BTT Arena
ARENA_SIG="BTT_ARENA_INFO"

# Offset to first arena
ARENA_OFF=8192

#
# check_file -- check if file exists and print error message if not
#
check_file()
{
	if [ ! -f $1 ]
	then
		echo "Missing file: ${1}"
		exit 1
	fi
}

#
# get_size -- return size of file
#
get_size()
{
	stat -c%s $1
}

#
# get_mode -- return mode of file
#
get_mode()
{
	stat -c%a $1
}

#
# check_size -- validate file size
#
check_size()
{
	local size=$1
	local file=$2
	local file_size=$(get_size $file)

	if [[ $size != $file_size ]]
	then
		echo "error: wrong size ${file_size} != ${size}"
		exit 1
	fi
}

#
# check_mode -- validate file mode
#
check_mode()
{
	local mode=$1
	local file=$2
	local file_mode=$(get_mode $file)

	if [[ $mode != $file_mode ]]
	then
		echo "error: wrong mode ${file_mode} != ${mode}"
		exit 1
	fi
}

#
# check_signature -- check if file contains specified signature
#
check_signature()
{
	local sig=$1
	local file=$2
	local file_sig=$(dd if=$file bs=1 count=$SIG_LEN 2>/dev/null)

	if [[ $sig != $file_sig ]]
	then
		echo "error: signature doesn't match ${file_sig} != ${sig}"
		exit 1
	fi
}

#
# check_arena -- check if file contains specified arena signature
#
check_arena()
{
	local file=$1
	local sig=$(dd if=$file bs=1 skip=$ARENA_OFF count=$ARENA_SIG_LEN 2>/dev/null)

	if [[ $sig != $ARENA_SIG ]]
	then
		echo "error: can't find arena signature"
		exit 1
	fi
}
