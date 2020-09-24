#!/bin/bash -e

echo "Syncer started";

STOP_REQUESTED=false
trap "STOP_REQUESTED=true" TERM INT

ITERATIONS_DONE=0

while true; do

    ITERATIONS_DONE=$((ITERATIONS_DONE + 1))
    if (( ITERATIONS_DONE > 5000 )); then
        echo "Recycling. Docker restart policy must restart the container!"
        exit 0
    fi

    for i in $(seq 1 10); do
        $STOP_REQUESTED || sleep 1
    done

    for branch in $(cat /repos/branches.txt); do

        if $STOP_REQUESTED; then
            echo "Terminating due to signal"
            exit 0
        fi

        if ! [[ "$branch" =~ ^[1-9][0-9]_[1-9]$ ]]; then
            echo Unsupported branch name
            exit 1
        fi

        echo "Syncing $branch -----------------------------------------"

        hg_path=/repos/$branch/hg
        gh_path=/repos/$branch/github
        asp_demos_path=/repos/$branch/asp-demos
        wg_external_path=$hg_path/Demos/WidgetsGallery/ExternalDemoSources

        demos_on_github_path=/repos/$branch/demos-on-github
        demos_on_github_hg_path=$hg_path/Demos/WidgetsGallery/WidgetsGallery
        wg_mvc_demos_path=$hg_path/Demos/WidgetsGallery/WidgetsGallery.MVC

        crossplatform_core_path=/repos/$branch/crossplatform-core
        data_portions_path=$hg_path/Tools/DevExpress.Data.Portions

        if ! /hg-update.sh $hg_path $branch; then
            echo "Failed to update HG repo"
            break
        fi

        /git-update.sh $gh_path $branch $gh_path.log \
            && /rsync-multi.sh $gh_path $hg_path/GitHub / \
            && /hg-commit.sh $hg_path $gh_path.log \
            || echo "Sync from GitHub failed"

        if [ -d $asp_demos_path ]; then
            if [[ $branch > "20_1"  ]]; then
                demo_shell_path=$hg_path/Demos/WidgetsGallery/AspNetCoreDemos.DemoShell
            else
                demo_shell_path=$hg_path/Demos/WidgetsGallery/WidgetsGallery.MVC/DevExtreme.NETCore.Demos
            fi
            /git-update.sh $asp_demos_path 20${branch/_/.} $asp_demos_path.log \
                && /rsync-multi.sh $asp_demos_path/AspNetCoreDemos.DemoShell $demo_shell_path DemoShell/ wwwroot/DemoShell/ .editorconfig \
                && /rsync-multi.sh $asp_demos_path $wg_external_path AspNetCoreDemos.Reporting/ AspNetCoreDemos.RichEdit/ AspNetCoreDemos.Spreadsheet/ \
                && find $wg_external_path -type f -regextype posix-egrep -not -regex ".*(README|menuMeta\.json|DemosStyles.*css|DemosScripts.*js|\.(cs|cshtml|md))$" -delete \
                && /hg-commit.sh $hg_path $asp_demos_path.log \
                || echo "Sync from ASP/Demos failed"
        fi

        if [ -d $crossplatform_core_path ]; then
            /git-update.sh $crossplatform_core_path 20${branch/_/.} $crossplatform_core_path.log \
            && /rsync-multi.sh $crossplatform_core_path/Win/DevExpress.Data/DevExpress.Data $data_portions_path AssemblyVersion.cs Utils/Logify.cs Utils/UAlgo.cs Utils/UAlgoConstants.cs Utils/UAlgoPost.cs Utils/UData.cs Utils/UTest.cs \
            && /hg-commit.sh $hg_path $crossplatform_core_path.log \
            || echo "Sync from CrossPlatform/Core failed"
        fi

        if [ -d $demos_on_github_path ]; then
            /git-update.sh $demos_on_github_path $branch $demos_on_github_path.log \
            && /rsync-multi.sh $demos_on_github_path $demos_on_github_hg_path utils/ JSDemos/ package.json \
            && /rsync-multi.sh $demos_on_github_path/MVCDemos $wg_mvc_demos_path/DevExtreme.MVC.Demos / \
            && /rsync-multi.sh $demos_on_github_path/NetCoreDemos $wg_mvc_demos_path/DevExtreme.NETCore.Demos / \
            && /hg-commit.sh $hg_path $demos_on_github_path.log \
            || echo "Sync from Demos/WidgetsGallery/WidgetsGallery failed"
        fi

        if ! /hg-push.sh $hg_path $branch; then
            echo "Failed to push HG repo"
        fi
    done

done
