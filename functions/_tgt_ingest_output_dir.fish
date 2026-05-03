# Where bloodhound-python should write its output for the active
# target. Echoes the path on stdout; empty output means "caller stays
# in CWD" (workspace not set up, or active target's folder doesn't
# exist on disk).
function _tgt_ingest_output_dir
    set -q TGT_SCENARIO; or return
    set -l target ""
    set -q TGT_ACTIVE; and set target $TGT_ACTIVE
    set -l dir (_tgt_workspace_dir $TGT_SCENARIO $target)
    test -d $dir; or return
    echo "$dir/loot"
end
