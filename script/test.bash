#! /bin/bash
#
# Copyright (c) 2013, Intel Corporation
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#  * Neither the name of Intel Corporation nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# This script executes ptt tests and compares the output of tools, like
# ptxed or ptdump, with the expected output from the ptt testfile.

check_tools() {
	local status=0
	for i in "$@"; do
		if [[ -z "`which $i`" ]]; then
			echo "$i: not in PATH" >&2
			status=1
		fi
	done
	return $status
}

info() {
	[[ $verbose != 0 ]] && echo -e "$@" >&2
}

run() {
	info "$@"
	"$@"
}

asm2addr() {
	local line
	line=`grep -i ^org $1`
	[[ $? != 0 ]] && return $?
	echo $line | sed "s/org *//"
}

usage() {
	cat <<EOF
usage: $0 [<options>] <pttfile>...

options:
  -h            this text
  -v            print commands as they are executed
  -c cpu[,cpu]  comma-separated list of cpu's for the tests (see pttc -h, for valid values)

  <pttfile>     annotated yasm file ending in .ptt
EOF
}

verbose=0
while getopts "hvc:" option; do
	case $option in
	h)
		usage
		exit 0
		;;
	v)
		verbose=1
		;;
	c)
		cpus=`echo $OPTARG | sed "s/,/ /g"`
		;;
	\?)
		exit 1
		;;
	esac
done

shift $(($OPTIND-1))

if [[ $# == 0 ]]; then
	usage
	exit 1
fi

# check if all the tools are in PATH
check_tools pttc yasm ptxed ptdump || exit 1

# the exit status
# indicates a "unknown tool" or non-empty diff fails.
status=0

run-ptt-test() {
	info "\n# run-ptt-test $@"

	ptt="$1"
	cpu="$2"
	base=`basename ${ptt%%.ptt}`

	if [[ -n "$cpu" ]]; then
		cpu="--cpu $cpu"
	fi

	# the following are the files that are generated by pttc
	pt=$base.pt
	bin=$base.bin
	lst=$base.lst


	# execute pttc
	exps=`run pttc $cpu $ptt`
	if [[ $? != 0 ]]; then
		echo "warning: pttc failed with $ptt" >&2
		continue
	elif [[ -z $exps ]]; then
		echo "warning: pttc did not produce any exp file for $ptt" >&2
		continue
	fi

	# loop over all .exp files determine the tool, generate .out
	# files and compare .exp and .out file with diff.
	# all differences will be
	for exp in $exps; do
		exp_base=${exp%%.exp}
		out=$exp_base.out
		diff=$exp_base.diff
		tool=${exp_base##$base-}
		tool=${tool%%-cpu_*}
		case $tool in
		ptxed)
			addr=`asm2addr $ptt`
			if [[ $? != 0 ]]; then
				echo "$ptt: org directive not found in test file" >&2
				continue
			fi
			run ptxed $cpu --pt $pt --raw $bin:$addr --no-inst > $out
			;;
		ptdump)
			run ptdump $cpu --lastip --fixed-offset-width $pt > $out
			;;
		*)
			echo "$ptt: unknown tool $tool"
			status=1
			continue
			;;
		esac
		if run diff -u $exp $out > $diff; then
			run rm $diff
		else
			echo $diff
		fi
	done
}

ptt-cpus() {
	sed -n 's/[ \t]*;[ \t]*cpu[ \t][ \t]*\(.*\)[ \t]*/\1/p' "$1"
}

run-ptt-tests() {
	local cpus=$cpus

	# if no cpus are given on the command-line,
	# use the cpu directives from the pttfile.
	if [[ -z $cpus ]]; then
		cpus=`ptt-cpus $ptt`
	fi

	# if there are no cpu directives in the pttfile,
	# run the test without any cpu settings.
	if [[ -z $cpus ]]; then
		run-ptt-test $ptt
		continue
	fi

	# otherwise run for each cpu the test.
	for i in $cpus; do
		run-ptt-test $ptt $i
	done
}

for ptt in "$@"; do
	run-ptt-tests $ptt
done

exit $status
