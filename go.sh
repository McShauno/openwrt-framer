#!/bin/bash

# include commonly used functions and variables. 
source common/boilerplate.sh

declare -a ON_TRAP_COMMANDS

readonly CONSTRUCT=$(cat construct.json)
readonly FRAMER_DIR=$(pwd)
shopt -s expand_aliases
shopt -s dotglob

get_construct() {
    local construct_name=$1
    echo $CONSTRUCT | ./common/jq -r $construct_name
}

apply_patches() {
    local subdirectory=$1
    local patch_target=$2
    local patch_directory=${FRAMER_DIR}/${subdirectory}
    local files=${patch_directory}/*.patch
    local total_files=$(ls -1 $files | wc -l)

    logline "Total patch files to process: $total_files"

    for patch_file in ${files}
    do
        logline "Applying patch file ${patch_file}"
        patch -d $patch_target -p1 -i ${patch_file}
    done
}

clone_repository() {
    local repo=$1
    local branch=$2
    local target=$3
    logline "Cloning git repository from ${repo} - ${branch} to ${target}"
    git clone -b $branch --single-branch $repo $target
    logline "Cloning complete."
}

execute_external() {
    local external_script=$1
    if [ -e $1 ]
    then
        source $1
    else
        logline "Warning: $1 does not exist."
    fi
}

copy_structure() {
    local structure=$1
    local target=$2
    logline "Copying base structure files to repo."
    cp --verbose --recursive ./${structure}/* ./${target}/
}

add_on_exit()
{
    local n=${#ON_TRAP_COMMANDS[*]}
    ON_TRAP_COMMANDS[$n]="$*"
    if [[ $n -eq 0 ]]; then
        logline "Appending Trap: $*"
        trap on_exit EXIT
    fi
}

on_exit()
{
    for i in "${ON_TRAP_COMMANDS[@]}"
    do
        echo "on_exit: $i"
        eval $i
    done

    exit 1
}

execute_plans() {
    local target=$1
    while 
        IFS= read -r plan_name &&
        IFS= read -r plan_pre &&
        IFS= read -r plan_structure &&
        IFS= read -r plan_patches &&
        IFS= read -r plan_pos;
    do
        logline "Executing plan $plan_name."
        execute_external ./${plan_name}/${plan_pre}
        copy_structure ${plan_name}/${plan_structure} ${target}/feeds/${plan_name}
        apply_patches ${plan_name}/${plan_patches} ${target}/feeds/${plan_name}
        execute_external ./${plan_name}/${plan_pos}
    done < <(echo $CONSTRUCT | ./common/jq -r '.plans[] | (.name, .prebuild, .structureDirectory, .patchesDirectory, .postbuild)')
}

main() {
    logline "Applying custom OpenWrt build..."

    local construct_name=$(get_construct '.name')
    local repository_url=$(get_construct '.openwrt.repository.url')
    local repository_branch=$(get_construct '.openwrt.repository.branch')
    local repository_target=$(get_construct '.openwrt.repository.target')

    clone_repository $repository_url $repository_branch $repository_target

    local base_pre=$(get_construct '.base.prebuild')
    local base_structure=$(get_construct '.base.structureDirectory')
    local base_patches=$(get_construct '.base.patchesDirectory')
    local base_post=$(get_construct '.base.postbuild')

    logline "Executing base prebuild script ${base_pre}."
    execute_external ./${base_pre}

    logline "Copying base structure."
    copy_structure $base_structure $repository_target

    logline "Applying base patches."
    apply_patches $base_patches $repository_target

    logline "Executing base post script ${base_post}."
    execute_external ./${base_post}

    logline "Executing additional plans..."
    execute_plans ${repository_target}

    local final_script=$(get_construct '.finalize')

    logline "Executing final script..."
    execute_external ./${final_script}

    logline "Complete."
}

main "$@"
