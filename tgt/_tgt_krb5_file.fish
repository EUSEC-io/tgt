# Path to the krb5 config. Override via $TGT_KRB5_FILE for tests.
function _tgt_krb5_file
    if set -q TGT_KRB5_FILE
        echo $TGT_KRB5_FILE
    else
        echo /etc/krb5.conf
    end
end
