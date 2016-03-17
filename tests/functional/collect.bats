#!/usr/bin/env bats
load common
load helpers
load env_setup

FIXTURES="$FIXTURES/collect"
WORKDIR="$FIXTURES"/.lago
PREFIX="$WORKDIR"/default
REPO_STORE="$FIXTURES"/repo_store
REPO_CONF="$FIXTURES"/template_repo.json
REPO_NAME="local_tests_repo"


@test "collect: setup" {
    local suite="$FIXTURES"/suite.yaml

    rm -rf "$REPO_STORE" "$WORKDIR"
    cp -a "$FIXTURES/store_skel" "$REPO_STORE"
    env_setup.populate_disks "$REPO_STORE"

    pushd "$FIXTURES"
    export BATS_TMPDIR BATS_TEST_DIRNAME
    export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
    helpers.run_ok "$LAGOCLI" \
        init \
        --template-repo-path "$REPO_CONF" \
        --template-repo-name "$REPO_NAME" \
        --template-store "$REPO_STORE" \
        "$suite"
    helpers.run_ok "$LAGOCLI" start
}

@test "collect: fails if files to collect don't exist" {
    common.is_initialized "$WORKDIR" || skip "Workdir not initiated"
    pushd "$FIXTURES"
    outdir="$FIXTURES/output"
    rm -rf "$outdir"
    helpers.run_nook "$LAGOCLI" collect --output "$outdir"
}


@test "collect: generate some logs" {
    common.is_initialized "$WORKDIR" || skip "Workdir not initiated"
    pushd "$FIXTURES"
    helpers.run_ok "$LAGOCLI" shell vm01 <<EOC
        echo "mytest" > /var/log/something.log
        echo "mytest2" > /var/log/something_else.log
EOC
}


@test "collect: collect from live vm without guest agent" {
    common.is_initialized "$WORKDIR" || skip "Workdir not initiated"
    pushd "$FIXTURES"
    outdir="$FIXTURES/output"
    logfiles=(
        "something.log"
        "something_else.log"
    )

    rm -rf "$outdir"
    helpers.run_ok "$LAGOCLI" collect --output "$outdir"

    for host in vm01; do
        helpers.is_dir "$outdir/$host"
        logdir="$outdir/$host"
        helpers.is_dir "$logdir"
        for logfile in "${logfiles[@]}"; do
            local_logfile="$logdir/_var_log_$logfile"
            helpers.is_file "$local_logfile"
            helpers.run_ok "$LAGOCLI" \
                shell "$host" \
                cat "/var/log/$logfile"
            helpers.diff_output "$local_logfile"
        done
    done
}


@test "collect: stop prefix" {
    common.is_initialized "$WORKDIR" || skip "Workdir not initiated"
    pushd "$FIXTURES"
    helpers.run_ok "$LAGOCLI" stop
}


@test "collect: collect from stopped vm" {
    common.is_initialized "$WORKDIR" || skip "Workdir not initiated"
    pushd "$FIXTURES"
    outdir="$FIXTURES/output"
    declare -A logfiles=(
        ["something.log"]='mytest'
        ["something_else.log"]='mytest2'
    )

    rm -rf "$outdir"
    helpers.run_ok "$LAGOCLI" collect --output "$outdir"

    for host in vm01; do
        helpers.is_dir "$outdir/$host"
        logdir="$outdir/$host"
        helpers.is_dir "$logdir"
        for logfile in "${!logfiles[@]}"; do
            local_logfile="$logdir/_var_log_$logfile"
            helpers.is_file "$local_logfile"
            run echo -e "\n${logfiles[$logfile]}"
            helpers.diff_output "$local_logfile"
        done
    done
}



@test "collect: teardown" {
    if common.is_initialized "$WORKDIR"; then
        pushd "$FIXTURES"
        helpers.run_ok "$LAGOCLI" destroy -y
        popd
    fi
    env_setup.destroy_domains
    env_setup.destroy_nets
}
