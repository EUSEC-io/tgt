# Execute bloodhound-python against the active target's AD domain.
function _tgt_run_bloodhound
    set -l bh_user $argv[1]
    set -l bh_pass $argv[2]
    set -l collection $argv[3]
    set -l do_zip $argv[4]
    set -l zip_name $argv[5]

    if not set -q TGT_AD_DOMAIN; or not set -q TGT
        echo "✗ Error: TGT_AD_DOMAIN and TGT must be set to run BloodHound."
        return 1
    end
    if not type -q bloodhound-python
        echo "✗ Error: bloodhound-python is not installed or not in PATH."
        return 1
    end

    set -l ns_target $TGT
    if set -q TGT_DC
        set ns_target $TGT_DC
    end

    echo "  [*] Executing bloodhound-python against $TGT_AD_DOMAIN..."
    bloodhound-python -u "$bh_user" -p "$bh_pass" -d "$TGT_AD_DOMAIN" -ns "$ns_target" -c "$collection"

    if test $status -eq 0
        if test "$do_zip" = true
            set -l json_files (ls *.json 2>/dev/null)
            if test (count $json_files) -gt 0
                echo "  [*] Zipping results into $zip_name..."
                zip -m -q "$zip_name" *.json
                echo "  ✓ Successfully created $zip_name"
            else
                echo "  ✗ No JSON files generated."
            end
        else
            echo "  ✓ BloodHound ingest complete. JSON files left in current directory."
        end
    else
        echo "  ✗ bloodhound-python encountered an error."
        return 1
    end
end
