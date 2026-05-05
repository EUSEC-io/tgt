# Execute bloodhound-python against the active target's AD domain.
function _tgt_run_bloodhound
    set -l bh_user $argv[1]
    set -l bh_pass $argv[2]
    set -l collection $argv[3]
    set -l do_zip $argv[4]
    set -l zip_name $argv[5]

    if not set -q TGT_DC_DOMAIN; or not set -q TGT
        echo "✗ Error: an active DC and TGT must be set — run `tgt dc switch` and `tgt switch <target>`."
        return 1
    end
    if not type -q bloodhound-python
        echo "✗ Error: bloodhound-python is not installed or not in PATH."
        return 1
    end

    set -l ns_target $TGT
    if set -q TGT_DC_IP
        set ns_target $TGT_DC_IP
    else if set -q TGT_DC
        set ns_target $TGT_DC
    end

    # Auto-route output into the active target's loot/ folder if the
    # workspace is set up. Otherwise stay in CWD (existing behavior).
    set -l output_dir (_tgt_ingest_output_dir)
    set -l before_pwd $PWD
    if test -n "$output_dir"
        if not mkdir -p -- $output_dir
            echo "✗ Error: cannot create $output_dir"
            return 1
        end
        cd -- $output_dir
        echo "  [*] Output directory: $output_dir"
    end

    echo "  [*] Executing bloodhound-python against $TGT_DC_DOMAIN..."
    bloodhound-python -u "$bh_user" -p "$bh_pass" -d "$TGT_DC_DOMAIN" -ns "$ns_target" -c "$collection"
    set -l bh_status $status

    if test $bh_status -eq 0
        if test "$do_zip" = true
            set -l json_files (ls *.json 2>/dev/null)
            if test (count $json_files) -gt 0
                echo "  [*] Zipping results into $zip_name..."
                zip -m -q "$zip_name" *.json
                echo "  ✓ Successfully created $zip_name in "(pwd)
            else
                echo "  ✗ No JSON files generated."
            end
        else
            echo "  ✓ BloodHound ingest complete. JSON files left in "(pwd)
        end
    else
        echo "  ✗ bloodhound-python encountered an error."
    end

    test -n "$output_dir"; and cd -- $before_pwd
    return $bh_status
end
