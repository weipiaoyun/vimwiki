#!/usr/bin/env bash

# credit to https://github.com/w0rp/ale for script ideas and the color vader
# output function.

printHelp() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Runs Vimwiki Vader tests or Vint in a Docker container"
    echo ""
    echo "-h Print help message"
    echo ""
    echo "-n Specify vim/nvim version to run tests for."
    echo "   Multiple versions can be specified by quoting the value and"
    echo "   separating versions with a space. E.g. -v \"vim1 vim2\"."
    echo "   Default is all available versions."
    echo ""
    echo "-l List available versions that can be used with the '-v' option"
    echo ""
    echo "-t Select test type: 'vader', 'vint', or 'all'"
    echo ""
    echo "-v Turn on verbose output."
    exit 0
}

printVersions() {
    # print the names of all vim/nvim versions
    getVers
}

runVader() {
    echo "Starting Docker container and Vader tests."

    # run tests for each specified version
    for v in $vers; do
        echo ""
        echo "Running version: $v"
        vim="/vim-build/bin/$v -u test/vimrc -i NONE"
        test_cmd="for VF in test/independent_runs/*.vader; do $vim \"+Vader! \$VF\"; done"

        set -o pipefail

        # tests that must be run in individual vim instances
        # see README.md for more information
        docker run -a stderr -e VADER_OUTPUT_FILE=/dev/stderr "${flags[@]}" \
          /bin/bash -c "$test_cmd" 2>&1 | vader_filter | vader_color

        # remaining tests
        docker run -a stderr -e VADER_OUTPUT_FILE=/dev/stderr "${flags[@]}" \
          "$v" -u test/vimrc -i NONE "+Vader! test/*" 2>&1 | vader_filter | vader_color
        set +o pipefail

    done
}

runVint() {
    echo "Starting Docker container and running Vint."

    docker run -a stdout "${flags[@]}" vint -s .
}

getVers() {
    sed -n 's/.* -name \([^ ]*\) .*/\1/p' ../Dockerfile
}

vader_filter() {
    local err=0
    while read -r; do
        if [[ "$verbose" == 0 ]]; then
            # only print possible error cases
            if [[ "$REPLY" = *'docker:'* ]] || \
               [[ "$REPLY" = *'Starting Vader:'* ]] || \
               [[ "$REPLY" = *'Vader error:'* ]] || \
               [[ "$REPLY" = *'Vim: Error '* ]]; then
                echo "$REPLY"
            elif [[ "$REPLY" = *'[EXECUTE] (X)'* ]] || \
                [[ "$REPLY" = *'[ EXPECT] (X)'* ]]; then
                echo "$REPLY"
                err=1
            elif [[ "$REPLY" = *'Success/Total:'* ]]; then
                success="$(echo -n "$REPLY" | grep -o '[0-9]\+/' | head -n1 | cut -d/ -f1)"
                total="$(echo -n "$REPLY" | grep -o '/[0-9]\+' | head -n1 | cut -d/ -f2)"
                if [ "$success" -lt "$total" ]; then
                    err=1
                fi
                echo "$REPLY"
            fi
        else
            # just print everything
            echo "$REPLY"
        fi
    done

    if [[ "$err" == 1 ]]; then
        echo ""
        echo "!---------Failed tests detected---------!"
        echo "Run with the '-v' flag for verbose output"
        echo ""
    fi
}

red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'
vader_color() {
    while read -r; do
        if [[ "$REPLY" = *'[EXECUTE] (X)'* ]] || \
            [[ "$REPLY" = *'[ EXPECT] (X)'* ]] || \
            [[ "$REPLY" = *'Vim: Error '* ]] || \
            [[ "$REPLY" = *'Vader error:'* ]]; then
            echo -en "$red"
        elif [[ "$REPLY" = *'[EXECUTE]'* ]] || [[ "$REPLY" = *'[  GIVEN]'* ]]; then
            echo -en "$nc"
        fi

        if [[ "$REPLY" = *'Success/Total'* ]]; then
            success="$(echo -n "$REPLY" | grep -o '[0-9]\+/' | head -n1 | cut -d/ -f1)"
            total="$(echo -n "$REPLY" | grep -o '/[0-9]\+' | head -n1 | cut -d/ -f2)"

            if [ "$success" -lt "$total" ]; then
                echo -en "$red"
            else
                echo -en "$green"
            fi

            echo "$REPLY"
            echo -en "$nc"
        else
            echo "$REPLY"
        fi
    done

    echo -en "$nc"
}

# list of vim/nvim versions
vers="$(getVers)"

# type of tests to run - vader/vint/all
type="all"

# verbose output flag
verbose=0

# docker flags
flags=(--rm -v "$PWD/../:/testplugin" -v "$PWD/../test:/home" -w /testplugin vimwiki)

while getopts ":hvn:lt:" opt; do
    case ${opt} in
        h )
            printHelp
            ;;
        n )
            vers="$OPTARG"
            ;;
        v )
            verbose=1
            ;;
        l )
            printVersions
            ;;
        t )
            type="$OPTARG"
            ;;
        \? )
            echo "Invalid option: $OPTARG" 1>&2
            exit 1
            ;;
        : )
            echo "Invalid option: $OPTARG requires an argument" 1>&2
            exit 1
            ;;
    esac
done

# shift out processed parameters
shift $((OPTIND -1))

# error handling for non-option arguments
if [[ $# -ne 0 ]]; then
    echo "Error: Got $# non-option arguments." 1>&2
    exit 1
fi

# stop tests on ctrl-c or ctrl-z
trap exit 1 SIGINT SIGTERM

# select which tests should run
case $type in
    "vader" )
        runVader
        ;;
    "vint" )
        runVint
        ;;
    "all" )
        runVint
        runVader
        ;;
    * )
        echo "Error: invalid type - '$type'" 1>&2
        exit 1
esac
